conda create -n api_extract_env python=3.9 --yes
conda activate api_extract_env
conda install conda-forge::requests --yes
pip install python-dotenv