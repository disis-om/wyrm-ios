"""Capture curated themes in both modes, plus restrained-accent extremes."""
from pathlib import Path
import os,subprocess,time
device=os.environ['WYRM_SIMULATOR']
out=Path('original-artifacts');out.mkdir(exist_ok=True)
themes=[(name,mode) for name in ['sand','linen','grape','cyan','metal3','midnight','colonial3'] for mode in ['light','dark']]
themes += [('classic_'+name,'dark' if name in ['graphite','midnight'] else 'light') for name in ['paper','graphite','blush','sun','slate','lilac','forest','midnight']]
pages=['play','lobby']
def run(*args,check=True):
 return subprocess.run(['xcrun','simctl',*args],check=check,timeout=45,stdout=subprocess.DEVNULL)
for theme,mode in themes:
 for intensity in (['0','0.5','1'] if theme in ['grape','cyan','metal3','colonial3'] and mode=='dark' else ['0.5']):
  for page in pages:
   stem=f'theme-{theme}-{mode}-{intensity}-{page}'
   run('terminate',device,'com.omrajput.wyrmios',check=False)
   args=['--smoke-lobby'] if page=='lobby' else ['--smoke-settings','--smoke-theme-page','play' if page=='arenas' else page]
   if page=='arenas':args+=['--smoke-theme-arenas']
   # Intentional simulator termination must not masquerade as an unclean
   # previous session. NSArgumentDomain overrides only that running marker;
   # real signal/exception files are still collected by the crash watcher.
   run('launch','--stdout='+str((out/(stem+'-stdout.log')).resolve()),'--stderr='+str((out/(stem+'-stderr.log')).resolve()),device,'com.omrajput.wyrmios',*args,'--smoke-theme',theme,'--smoke-theme-mode',mode,'--smoke-theme-intensity',intensity,'-wyrm.crash.running','NO')
   time.sleep(3)
   run('io',device,'screenshot',str(out/(stem+'.png')))
   print('Captured',stem,flush=True)
run('terminate',device,'com.omrajput.wyrmios',check=False)
print('Theme matrix: 60 actual simulator screenshots; seven current themes plus eight classics')
