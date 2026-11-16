"""ParkControl - Flask + MySQL. Ejecutar: python app.py  (ver variables DB_* abajo)."""
import os, re
from datetime import date, datetime, timedelta
from functools import wraps
import pymysql
from pymysql.cursors import DictCursor
from flask import Flask, g, render_template, request, redirect, url_for, session, flash, abort
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY', 'cambiar-esta-clave')
PRECIO = {'Carro': 250000, 'Moto': 100000}
PLACA = re.compile(r'^[A-Z]{3}\d{2}[A-Z0-9]$')          # ABC123 (carro) / MNP45F (moto)


# ---------------- Persistencia ----------------
def db():
    if 'db' not in g:
        g.db = pymysql.connect(host=os.getenv('DB_HOST', 'localhost'), port=int(os.getenv('DB_PORT', 3306)),
                               user=os.getenv('DB_USER', 'root'), password=os.getenv('DB_PASS', ''),
                               database=os.getenv('DB_NAME', 'parkcontrol_db'), charset='utf8mb4', cursorclass=DictCursor)
    return g.db

@app.teardown_appcontext
def cerrar(_):
    c = g.pop('db', None)
    if c: c.close()

def q(sql, args=(), one=False):
    with db().cursor() as cur:
        cur.execute(sql, args)
        return cur.fetchone() if one else cur.fetchall()

def w(sql, args=()):
    with db().cursor() as cur:
        cur.execute(sql, args); db().commit(); return cur.lastrowid


# ---------------- Seguridad ----------------
def admin_required(f):
    @wraps(f)
    def inner(*a, **k):
        if session.get('rol') != 'Administrador': abort(403)
        return f(*a, **k)
    return inner

@app.before_request
def antes():
    if request.endpoint in (None, 'static', 'login'): return
    if 'uid' not in session: return redirect(url_for('login'))
    w("UPDATE MENSUALIDAD SET estado='Vencida' WHERE estado='Vigente' AND vencimiento_fecha < NOW()")

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        u = q("SELECT * FROM OPERADOR WHERE usuario=%s", (request.form['usuario'].strip(),), one=True)
        if u and u['estado'] == 'Activo' and check_password_hash(u['clave_hash'], request.form['clave']):
            session.clear(); session.update(uid=u['id_operador'], nombre=u['nombre'], rol=u['rol'])
            return redirect(url_for('entrada'))
        flash('Usuario o contraseña incorrectos, o cuenta inactiva.', 'err')
    return render_template('login.html')

@app.route('/logout')                                    # "Cambiar cuenta" y "Salir"
def logout():
    session.clear(); return redirect(url_for('login'))


# ---------------- Entrada / salida ----------------
def cupos(): return {r['tipo']: r for r in q("SELECT * FROM v_cupos")}
def info(titulo, msg, tono='err'): return {'k': 'info', 'titulo': titulo, 'msg': msg, 'tono': tono}

def pagina_entrada(modal=None, placa='', tipo='Carro'):
    activas = q("""SELECT e.id_estancia, v.placa, v.tipo, c.codigo, e.hora_entrada, o.nombre operador
                   FROM ESTADIA e JOIN VEHICULO v USING(id_vehiculo) JOIN CELDA c USING(id_celda)
                   JOIN OPERADOR o USING(id_operador) WHERE e.hora_salida IS NULL
                   ORDER BY e.hora_entrada DESC LIMIT 10""")
    return render_template('entrada.html', cupos=cupos(), activas=activas, modal=modal, placa=placa, tipo=tipo)

@app.route('/')
def entrada(): return pagina_entrada()

@app.post('/ingreso')
def ingreso():
    placa, tipo = request.form['placa'].strip().upper(), request.form.get('tipo', 'Carro')
    v = q("SELECT * FROM VEHICULO WHERE placa=%s", (placa,), one=True)
    if not v: return pagina_entrada({'k': 'noreg', 'placa': placa, 'tono': 'warn'}, placa, tipo)
    if v['tipo'] != tipo:
        return pagina_entrada(info('Tipo de vehículo incorrecto', f"La placa {placa} está registrada como {v['tipo']}."), placa, v['tipo'])
    if v['estado'] == 'Inactivo':
        return pagina_entrada(info('Cuenta inactiva', f'El vehículo {placa} está inactivo. Un administrador debe reactivarlo.'), placa, tipo)
    m = q("SELECT * FROM MENSUALIDAD WHERE id_vehiculo=%s ORDER BY id_mensualidad DESC LIMIT 1", (v['id_vehiculo'],), one=True)
    if not m or m['estado'] != 'Vigente':
        return pagina_entrada({'k': 'vencida', 'v': v, 'valor': PRECIO[tipo], 'tono': 'err'}, placa, tipo)
    if q("SELECT 1 x FROM ESTADIA WHERE id_vehiculo=%s AND hora_salida IS NULL", (v['id_vehiculo'],), one=True):
        return pagina_entrada(info('Ingreso duplicado', f'La placa {placa} ya tiene un ingreso activo sin salida.'), placa, tipo)
    con = db()
    try:
        with con.cursor() as cur:
            cur.execute("SELECT id_celda, codigo FROM CELDA WHERE tipo=%s AND estado='Disponible' ORDER BY id_celda LIMIT 1 FOR UPDATE", (tipo,))
            c = cur.fetchone()
            if not c:
                con.rollback()
                return pagina_entrada(info('Ingreso denegado', f'Sin celdas disponibles para {tipo.lower()}s. Cupo lleno.'), placa, tipo)
            cur.execute("INSERT INTO ESTADIA (hora_entrada, id_celda, id_vehiculo, id_operador) VALUES (NOW(),%s,%s,%s)",
                        (c['id_celda'], v['id_vehiculo'], session['uid']))
            ticket = cur.lastrowid
            cur.execute("UPDATE CELDA SET estado='Ocupada' WHERE id_celda=%s", (c['id_celda'],))
        con.commit()
    except pymysql.err.IntegrityError:
        con.rollback()
        return pagina_entrada(info('Ingreso duplicado', f'La placa {placa} ya tiene un ingreso activo.'), placa, tipo)
    flash(f"Ingreso registrado: {placa} en la celda {c['codigo']} · ticket #{ticket}", 'ok')
    return redirect(url_for('entrada'))

@app.post('/salida')
def salida():
    ref = request.form['ref'].strip().upper()
    col = 'e.id_estancia' if ref.isdigit() else 'v.placa'   # acepta ID de ticket o placa
    e = q(f"""SELECT e.id_estancia, e.id_celda, v.placa, c.codigo FROM ESTADIA e JOIN VEHICULO v USING(id_vehiculo)
              JOIN CELDA c USING(id_celda) WHERE {col}=%s AND e.hora_salida IS NULL""", (ref,), one=True)
    if not e: return pagina_entrada(info('Sin estadía activa', f'No hay un ingreso activo para «{ref}».'))
    con = db()
    with con.cursor() as cur:
        cur.execute("UPDATE ESTADIA SET hora_salida=NOW() WHERE id_estancia=%s", (e['id_estancia'],))
        cur.execute("UPDATE CELDA SET estado='Disponible' WHERE id_celda=%s AND estado='Ocupada'", (e['id_celda'],))
    con.commit()
    return pagina_entrada(info('Salida procesada', f"Placa {e['placa']} · celda {e['codigo']} liberada.", 'ok'))

@app.post('/renovar/<int:vid>')
def renovar(vid):
    v = q("SELECT * FROM VEHICULO WHERE id_vehiculo=%s", (vid,), one=True) or abort(404)
    w("""INSERT INTO MENSUALIDAD (fecha_ingreso, vencimiento_fecha, estado, valor_pagado, id_vehiculo)
         VALUES (NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY), 'Vigente', %s, %s)""", (PRECIO[v['tipo']], vid))
    flash(f"Plan de {v['placa']} renovado por 30 días. Ya puede registrar el ingreso.", 'ok')
    return redirect(url_for('entrada'))


# ---------------- Usuarios ----------------
def limite(t): return q("SELECT COUNT(*) n FROM CELDA WHERE tipo=%s", (t,), one=True)['n']
def inscritos(t): return q("SELECT COUNT(*) n FROM v_inscripciones WHERE tipo=%s AND estado='Vigente'", (t,), one=True)['n']

@app.route('/usuarios')
def usuarios():
    f = {k: request.args.get(k, '').strip() for k in ('q', 'tipo', 'rol', 'estado')}
    rows = []
    if f['rol'] in ('', 'Cliente mensual'):
        est = "IF(v.estado='Inactivo','Inactivo',i.estado)"
        sql, a = f"""SELECT 'v' k, v.id_vehiculo id, v.placa titulo, v.tipo, CONCAT(v.marca,' ',v.modelo) vehiculo,
                     'Cliente mensual' rol, i.vencimiento_fecha vence, {est} estado
                     FROM VEHICULO v LEFT JOIN v_inscripciones i USING(id_vehiculo) WHERE 1=1""", []
        if f['q']: sql += " AND v.placa LIKE %s"; a.append(f"%{f['q']}%")
        if f['tipo']: sql += " AND v.tipo=%s"; a.append(f['tipo'])
        if f['estado']: sql += f" AND {est}=%s"; a.append(f['estado'])
        rows += q(sql + " ORDER BY v.placa", a)
    if f['rol'] in ('', 'Administrador', 'Operador') and not f['tipo'] and f['estado'] in ('', 'Activo', 'Inactivo'):
        sql, a = "SELECT 'o' k, id_operador id, nombre titulo, '—' tipo, '—' vehiculo, rol, NULL vence, estado FROM OPERADOR WHERE 1=1", []
        if f['q']: sql += " AND nombre LIKE %s"; a.append(f"%{f['q']}%")
        if f['rol']: sql += " AND rol=%s"; a.append(f['rol'])
        if f['estado']: sql += " AND estado=%s"; a.append(f['estado'])
        rows += q(sql + " ORDER BY nombre", a)
    return render_template('usuarios.html', rows=rows, f=f)

@app.route('/usuarios/nuevo', methods=['GET', 'POST'])
def nuevo_cliente():
    d = {k: (request.values.get(k) or '').strip() for k in ('placa', 'tipo', 'marca', 'modelo', 'color', 'inicio')}
    d['placa'], d['tipo'] = d['placa'].upper(), d['tipo'] or 'Carro'
    err = None
    if request.method == 'POST':
        if not all(d[k] for k in ('placa', 'marca', 'modelo', 'color')): err = 'Placa, marca, modelo y color son obligatorios.'
        elif not PLACA.match(d['placa']): err = 'Formato de placa inválido (ej: ABC123 o MNP45F).'
        elif q("SELECT 1 x FROM VEHICULO WHERE placa=%s", (d['placa'],), one=True): err = 'Esa placa ya está registrada.'
        elif inscritos(d['tipo']) >= limite(d['tipo']): err = f"No hay cupos de inscripción para {d['tipo'].lower()}s."
        else:
            ini = datetime.strptime(d['inicio'], '%Y-%m-%d') if d['inicio'] else datetime.now()
            con = db()
            with con.cursor() as cur:
                cur.execute("INSERT INTO VEHICULO (placa,tipo,marca,modelo,color) VALUES (%s,%s,%s,%s,%s)",
                            (d['placa'], d['tipo'], d['marca'], d['modelo'], d['color']))
                cur.execute("INSERT INTO MENSUALIDAD (fecha_ingreso,vencimiento_fecha,estado,valor_pagado,id_vehiculo) VALUES (%s,%s,'Vigente',%s,%s)",
                            (ini, ini + timedelta(days=30), PRECIO[d['tipo']], cur.lastrowid))
            con.commit()
            flash(f"Cliente {d['placa']} registrado y mensualidad cobrada. Ya puede ingresar.", 'ok')
            return redirect(url_for('entrada'))
    return render_template('nuevo.html', modo='c', d=d, err=err, hoy=date.today().isoformat())

@app.route('/usuarios/operarios/nuevo', methods=['GET', 'POST'])
@admin_required
def nuevo_operario():
    d = {k: (request.form.get(k) or '').strip() for k in ('nombre', 'telefono', 'usuario', 'rol')}
    clave, clave2, err = request.form.get('clave', ''), request.form.get('clave2', ''), None
    if request.method == 'POST':
        if not all(d.values()) or not clave: err = 'Todos los campos son obligatorios.'
        elif len(clave) < 8: err = 'La contraseña debe tener mínimo 8 caracteres.'
        elif clave != clave2: err = 'Las contraseñas no coinciden.'
        elif q("SELECT 1 x FROM OPERADOR WHERE usuario=%s", (d['usuario'],), one=True): err = 'Ese usuario ya existe.'
        else:
            w("INSERT INTO OPERADOR (nombre,telefono,usuario,clave_hash,rol) VALUES (%s,%s,%s,%s,%s)",
              (d['nombre'], d['telefono'], d['usuario'], generate_password_hash(clave), d['rol']))
            flash(f"Operario {d['nombre']} creado.", 'ok'); return redirect(url_for('usuarios'))
    return render_template('nuevo.html', modo='o', d=d, err=err)

@app.route('/usuarios/vehiculo/<int:vid>', methods=['GET', 'POST'])
def perfil(vid):
    v = q("SELECT * FROM VEHICULO WHERE id_vehiculo=%s", (vid,), one=True) or abort(404)
    if request.method == 'POST':
        if session['rol'] != 'Administrador': abort(403)
        d = {k: request.form[k].strip() for k in ('placa', 'marca', 'modelo', 'color')}; d['placa'] = d['placa'].upper()
        if not all(d.values()) or not PLACA.match(d['placa']): flash('Datos inválidos: revisa los campos y el formato de la placa.', 'err')
        elif q("SELECT 1 x FROM VEHICULO WHERE placa=%s AND id_vehiculo<>%s", (d['placa'], vid), one=True): flash('Esa placa ya existe.', 'err')
        else:
            w("UPDATE VEHICULO SET placa=%s, marca=%s, modelo=%s, color=%s WHERE id_vehiculo=%s", (*d.values(), vid))
            flash('Perfil actualizado.', 'ok'); return redirect(url_for('perfil', vid=vid))
    m = q("SELECT * FROM v_inscripciones WHERE id_vehiculo=%s", (vid,), one=True)
    hist = q("""SELECT e.hora_entrada, e.hora_salida, c.codigo FROM ESTADIA e JOIN CELDA c USING(id_celda)
                WHERE e.id_vehiculo=%s AND e.hora_entrada >= DATE_SUB(NOW(), INTERVAL 12 MONTH) ORDER BY e.hora_entrada DESC""", (vid,))
    return render_template('perfil.html', v=v, m=m, hist=hist)

@app.post('/usuarios/<k>/<int:id>/estado')
@admin_required
def estado(k, id):
    tabla, col = {'v': ('VEHICULO', 'id_vehiculo'), 'o': ('OPERADOR', 'id_operador')}.get(k) or abort(404)
    if k == 'o' and id == session['uid']:
        flash('No puedes inactivar tu propia cuenta.', 'err')
    elif request.form['accion'] == 'inactivar':
        w(f"UPDATE {tabla} SET estado='Inactivo', inactivo_hasta=DATE_ADD(CURDATE(), INTERVAL 12 MONTH) WHERE {col}=%s", (id,))
        flash('Cuenta inactivada por 12 meses; se puede reactivar en ese plazo.', 'ok')
    elif q(f"SELECT 1 x FROM {tabla} WHERE {col}=%s AND inactivo_hasta >= CURDATE()", (id,), one=True):
        w(f"UPDATE {tabla} SET estado='Activo', inactivo_hasta=NULL WHERE {col}=%s", (id,)); flash('Cuenta reactivada.', 'ok')
    else:
        flash('Pasaron los 12 meses: la cuenta ya no se puede reactivar.', 'err')
    return redirect(request.referrer or url_for('usuarios'))


# ---------------- Celdas ----------------
@app.route('/celdas')
def celdas():
    rows = q("""SELECT c.*, v.placa FROM CELDA c LEFT JOIN ESTADIA e ON e.id_celda=c.id_celda AND e.hora_salida IS NULL
                LEFT JOIN VEHICULO v ON v.id_vehiculo=e.id_vehiculo ORDER BY c.tipo, c.id_celda""")
    res = {r['estado']: r['n'] for r in q("SELECT estado, COUNT(*) n FROM CELDA GROUP BY estado")}
    return render_template('celdas.html', carros=[r for r in rows if r['tipo'] == 'Carro'], motos=[r for r in rows if r['tipo'] == 'Moto'], res=res)

@app.route('/celdas/<int:cid>', methods=['GET', 'POST'])
@admin_required
def celda(cid):
    c = q("SELECT * FROM CELDA WHERE id_celda=%s", (cid,), one=True) or abort(404)
    if request.method == 'POST':
        codigo, tipo, est = request.form['codigo'].strip().upper(), request.form.get('tipo', c['tipo']), request.form.get('estado', c['estado'])
        if c['estado'] == 'Ocupada': tipo, est = c['tipo'], 'Ocupada'     # una celda ocupada no cambia de tipo ni de estado
        try:
            w("UPDATE CELDA SET codigo=%s, tipo=%s, estado=%s WHERE id_celda=%s", (codigo, tipo, est, cid))
            flash(f'Celda {codigo} actualizada.', 'ok'); return redirect(url_for('celdas'))
        except pymysql.err.IntegrityError:
            flash('Ese código ya existe.', 'err')
    return render_template('celda.html', c=c)


# ---------------- Inscripciones y reportes (admin) ----------------
@app.route('/inscripciones')
@admin_required
def inscripciones():
    est = request.args.get('estado', '')
    mods = [{'tipo': t, 'limite': limite(t), 'inscritos': inscritos(t)} for t in ('Carro', 'Moto')]
    rows = q("SELECT * FROM v_inscripciones" + (" WHERE estado=%s" if est else "") + " ORDER BY vencimiento_fecha", (est,) if est else ())
    return render_template('inscripciones.html', mods=mods, rows=rows, est=est)

@app.route('/reportes')
@admin_required
def reportes():
    n = lambda sql: q(sql, one=True)['n']
    r = {'clientes': n("SELECT COUNT(*) n FROM VEHICULO"), 'vigentes': n("SELECT COUNT(*) n FROM v_inscripciones WHERE estado='Vigente'"),
         'vencidas': n("SELECT COUNT(*) n FROM v_inscripciones WHERE estado='Vencida'")}
    por_vencer = q("SELECT * FROM v_inscripciones WHERE estado='Vigente' AND dias_restantes BETWEEN 0 AND 7 ORDER BY vencimiento_fecha")
    res = {x['estado']: x['n'] for x in q("SELECT estado, COUNT(*) n FROM CELDA GROUP BY estado")}
    return render_template('reportes.html', r=r, por_vencer=por_vencer, res=res)


if __name__ == '__main__':
    host = os.getenv('FLASK_RUN_HOST', '0.0.0.0')
    port = int(os.getenv('FLASK_RUN_PORT', 5000))
    app.run(host=host, port=port, debug=True)
