#!/usr/bin/env python3
"""Generate Crispy Crust print resources. Requires reportlab; no remote inputs."""
from pathlib import Path
from html import escape
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4, letter
from reportlab.lib.colors import HexColor
from reportlab.pdfbase.pdfmetrics import stringWidth, registerFont
from reportlab.pdfbase.ttfonts import TTFont
registerFont(TTFont("PrintSans", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
registerFont(TTFont("PrintBold", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
registerFont(TTFont("PrintSerif", "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"))

OUT = Path(__file__).resolve().parents[1] / 'public' / 'downloads'
OUT.mkdir(parents=True, exist_ok=True)
INK = HexColor('#3c342a'); OLIVE = HexColor('#65704c'); LINE = HexColor('#c8c4b8')
resources = {
'starter-feeding-log': {
 'title':'Sourdough starter feeding log',
 'subtitle':'One feed. A few observations. A better comparison next time.',
 'note':'Mark the starting level after feeding. Use a straight-sided jar for height measurements. Record a peak window when the exact peak was missed; write unknown when the evidence is unclear.',
 'sections':[
  ('Feed details', [('Jar name / date',''),('Time fed / location',''),('Starter + flour + water','____ g starter + ____ g flour + ____ g water'),('Ratio / flour used',''),('Temperature / starting level','____ °C or °F     Starting level ____ cm or mL')]),
  ('Rise observations', [('Check time','Height or volume | Rising, near peak, falling or unknown'),('',''),('',''),('',''),('','')]),
  ('Next-feed decision', [('Peak window / unknown',''),('One change to try',''),('Why / what to check next','')])],
 'footer':'Compare similar flour, feeding ratio and temperature. A rise measurement is not a food-safety test.'
},
'sourdough-bake-journal': {
 'title':'Sourdough bake journal',
 'subtitle':'Record what happened. Change one thing on the next loaf.',
 'note':'Use one sheet per bake. Keep planned and actual times separate. Note whether rise readings come from the full dough or an aliquot sample.',
 'sections':[
  ('Formula and starter', [('Date / recipe / version',''),('Flour blend / total flour',''),('Added water / starter / salt','____ g water     ____ g starter     ____ g salt'),('Starter feed / ripeness / hydration','')]),
  ('Timing and dough observations', [('Mix: planned / actual / temperature',''),('Starting level / units / vessel',''),('Fold times / dough feel',''),('End of bulk: time / rise / feel',''),('Shape / proof: start / finish / temperature',''),('Preheat / load / lid off / finish','')]),
  ('After cooling', [('Cooling time / crumb / crust',''),('Photo filename or note',''),('One change for the next loaf','')])],
 'footer':'For a short record, keep the formula, mixed dough temperature, shaping observations and final result.'
},
'weekend-sourdough-schedule': {
 'title':'Weekend sourdough planning sheet',
 'subtitle':'Work backwards from the slice. Give the dough room to change pace.',
 'note':'Fill in the windows from your chosen recipe and your own kitchen. Times below are blank on purpose: fermentation readiness, oven time and cooling depend on the loaf.',
 'sections':[
  ('Start with serving and availability', [('Recipe / loaf size',''),('Target serving time',''),('Cooling / bake / preheat durations',''),('Times away from home','')]),
  ('Plan and actual times', [('Step','Planned time | Actual time / readiness observation'),('Build levain / feed starter',''),('Flour-and-water rest (if used)',''),('Mix / dough temperature',''),('Folds / check windows',''),('End of bulk / shape',''),('Proof start / temperature',''),('Preheat / score / load',''),('Bake finish / cooling / slice','')]),
  ('If the dough runs late', [('Next check / revised bake time',''),('Revised serving time','')])],
 'footer':'Use a recipe designed for its proofing method. Refrigeration slows fermentation gradually; it is not an indefinite pause.'
},
'sourdough-formula-card': {
 'title':'Sourdough formula card',
 'subtitle':'Choose the denominator before you calculate.',
 'note':'In a total-flour formula, count the flour and water carried by the starter. Do not add them twice if the recipe already includes them in its totals.',
 'sections':[
  ('Your recipe in grams', [('Recipe / version / target dough weight',''),('Added flour / flour blend',''),('Added water / starter / salt',''),('Starter hydration','')]),
  ('Split the starter', [('Starter flour','starter weight ÷ (1 + starter hydration ÷ 100)'),('Starter water','starter weight - starter flour'),('Total flour','added flour + starter flour'),('Total water','added water + starter water')]),
  ('Calculate and record', [('Dough hydration (%)','total water ÷ total flour × 100'),('Ingredient baker\'s percentage','ingredient weight ÷ chosen flour denominator × 100'),('Target scale factor','target dough weight ÷ original dough weight'),('Scaled formula / rounding notes',''),('','')]),
 ],
 'footer':'Example: 500 g flour + 350 g water + 100 g starter at 100% hydration = 550 g flour and 400 g water: 72.7% hydration.'
}}


resources['bulk-fermentation-chart'] = {
 'title':'Bulk fermentation reference chart',
 'subtitle':'A conditional reference, plus space for your own starting mark.',
 'note':"Reference: Tom Cucuzza, The Secret of Bulk Fermentation (The Sourdough Journey). Tartine-style formula: 90% bread flour, 10% whole wheat, 75% water, 20% starter, 2% salt. Bulk starts at starter addition; shaped cold proof is 12-16 hours near 3°C (37°F). These are method-specific checkpoints, not universal targets.",
 'sections':[
  ('Selected reference points', [('Dough temperature','Rise | Example mark from 400 mL start'),('27°C / 80°F','30% | 520 mL'),('24°C / 75°F','50% | 600 mL'),('21°C / 70°F','75% | 700 mL')]),
  ('Your formula and measurement', [('Recipe / flour blend / starter amount',''),('Final proof method / fridge temperature',''),('Starting reading / units / time',''),('Measured dough temperature',''),('Chosen recipe target / target mark','')]),
  ('Turn the target into a mark', [('Target reading','starting reading × (1 + target rise ÷ 100)'),('Measured rise (%)','(current reading - start) ÷ start × 100'),('Actual rise / dough feel at shaping',''),('Cooled crumb / next change','')])],
 'footer':'Use marked volume for flared tubs; height works only with straight sides. Read temperature, aeration and dough feel together. Source and full assumptions: crispycrust.app/journal/sourdough-bulk-fermentation-chart'
}

def wrap(text, width, font='PrintSans', size=9):
 words=text.split(); lines=[]; cur=''
 for word in words:
  trial=(cur+' '+word).strip()
  if stringWidth(trial,font,size)>width and cur: lines.append(cur); cur=word
  else: cur=trial
 if cur: lines.append(cur)
 return lines

def pdf_file(slug,data,fmt,size):
 path=OUT/f'{slug}-{fmt}.pdf'; c=canvas.Canvas(str(path),pagesize=size,pageCompression=1)
 c.setTitle(data['title']); c.setAuthor('Crispy Crust'); c.setSubject(data['subtitle'])
 w,h=size; x=42; right=w-42; width=right-x; y=h-43
 c.setFillColor(OLIVE); c.setFont('PrintBold',10); c.drawString(x,y,'CRISPY CRUST  /  THE BAKER\'S JOURNAL'); y-=31
 c.setFillColor(INK); title_size=min(25,25*width/stringWidth(data['title'],'PrintSerif',25)); c.setFont('PrintSerif',title_size); c.drawString(x,y,data['title']); y-=22
 c.setFont('PrintSans',10); c.drawString(x,y,data['subtitle']); y-=23
 c.setFont('PrintSans',9)
 for ln in wrap(data['note'],width): c.drawString(x,y,ln); y-=12
 y-=9
 rows=sum(len(rows) for _,rows in data['sections']); heading_space=29*len(data['sections']); avail=y-95-heading_space
 row_h=min(34,max(25,avail/rows))
 for title,items in data['sections']:
  c.setFillColor(OLIVE); c.setFont('PrintBold',10); c.drawString(x,y,title.upper()); y-=10
  for label,value in items:
   c.setStrokeColor(LINE); c.setLineWidth(.5); c.line(x,y-row_h,right,y-row_h)
   if label:
    c.setFillColor(INK); c.setFont('PrintBold',8.5)
    label_lines=wrap(label,width*.38,'PrintBold',8.5)
    for idx,ln in enumerate(label_lines[:2]): c.drawString(x+2,y-13-idx*10,ln)
   if value:
    c.setFont('PrintSans',8.5); c.setFillColor(INK)
    for idx,ln in enumerate(wrap(value,width*.59,'PrintSans',8.5)[:2]): c.drawString(x+width*.40,y-13-idx*10,ln)
   y-=row_h
  y-=19
 c.setFont('PrintSans',8); c.setFillColor(INK)
 fy=54
 for ln in wrap(data['footer'],width,'PrintSans',8): c.drawString(x,fy,ln); fy-=10
 c.setFont('PrintSans',7); c.setFillColor(OLIVE); c.drawString(x,25,'crispycrust.app  |  Free printable  |  '+('A4' if fmt=='a4' else 'US Letter'))
 c.showPage(); c.save()

def html_file(slug,data):
 sections=''
 for title,items in data['sections']:
  sections+='<section><h2>'+escape(title)+'</h2><table><tbody>'
  for label,value in items:
   sections+='<tr><th scope="row">'+escape(label or 'Observation')+'</th><td>'+escape(value or ' ')+'</td></tr>'
  sections+='</tbody></table></section>'
 content='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,follow"><title>'''+escape(data['title'])+''' | Crispy Crust</title><style>
:root{font-family:Arial,sans-serif;color:#3c342a}body{max-width:780px;margin:30px auto;padding:0 24px}a{color:#53623e}h1{font:32px Georgia,serif;margin-bottom:8px}h2{font-size:15px;text-transform:uppercase;color:#65704c;margin-top:25px}p{line-height:1.5}table{border-collapse:collapse;width:100%;table-layout:fixed}th,td{border-bottom:1px solid #c8c4b8;text-align:left;padding:10px 5px;vertical-align:top;min-height:25px;font-size:13px}th{width:36%}td{height:25px}footer{font-size:12px;margin:25px 0}.controls{padding:15px 0;display:flex;gap:15px;flex-wrap:wrap}button{background:#65704c;color:white;border:0;padding:9px 15px;border-radius:4px;cursor:pointer} .brand{font-size:12px;letter-spacing:2px;color:#65704c} @media print{body{margin:0;padding:0;max-width:none}.controls{display:none}h1{font-size:27px}h2{margin-top:17px}th,td{padding:7px 4px}section{break-inside:avoid}footer{margin:16px 0}@page{margin:15mm}}
</style></head><body><p class="brand">CRISPY CRUST / THE BAKER'S JOURNAL</p><h1>'''+escape(data['title'])+'''</h1><p>'''+escape(data['subtitle'])+'''</p><div class="controls"><button onclick="window.print()" type="button">Print this sheet</button><a href="'''+slug+'''-a4.pdf" download>A4 PDF</a><a href="'''+slug+'''-letter.pdf" download>US Letter PDF</a><a href="/journal">Back to the journal</a></div><p>'''+escape(data['note'])+'''</p>'''+sections+'''<footer><p>'''+escape(data['footer'])+'''</p><a href="https://www.crispycrust.app">crispycrust.app</a></footer></body></html>'''
 (OUT/f'{slug}.html').write_text(content)

for slug,data in resources.items():
 for fmt,size in [('a4',A4),('letter',letter)]: pdf_file(slug,data,fmt,size)
 html_file(slug,data)
print('Generated',len(resources)*3,'print resources in',OUT)
