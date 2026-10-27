import json,pathlib,sys
import mlx_whisper
cache=pathlib.Path.home()/'.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo/snapshots'
models=[p for p in cache.glob('*') if (p/'config.json').exists() and ((p/'weights.npz').exists() or (p/'weights.safetensors').exists())]
model=str(models[0]) if models else 'mlx-community/whisper-large-v3-turbo'
result=mlx_whisper.transcribe(sys.argv[1],path_or_hf_repo=model,language='en',word_timestamps=True,condition_on_previous_text=False,verbose=False)
words=[word for seg in result['segments'] for word in seg.get('words',[]) if float(word.get('probability',1))>=.25]
pathlib.Path(sys.argv[2]).write_text(json.dumps({'words':words},ensure_ascii=False))
