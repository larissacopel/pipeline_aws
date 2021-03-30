
from __future__ import print_function

import base64


def lambda_handler(event, context):

    # Lista que armazenará os registros processados
    output = []

    # Para cada registro recebido
    for record in event['records']:

        # Decodifica os dados
        payload = base64.b64decode(record['data'])

        # Transforma a string em um json
        dadosTrat = eval(payload)
        
        # Header do arquivo
        header = "\"id\",\"name\",\"abv\",\"ibu\",\"target_fg\",\"target_og\",\"ebc\",\"srm\",\"ph\""
        
        # Tratamento de dados nulos
        if dadosTrat['abv'] == 'None':
            abv = ''
        if dadosTrat['ibu'] == 'None':
            ibu = ''
        if dadosTrat['target_fg'] == 'None':
            target_fg = ''
        if dadosTrat['target_og'] == 'None':
            target_og = ''
        if if dadosTrat['ebc'] == 'None':
            ebc = ''
        if dadosTrat['srm'] == 'None':
            srm = ''
        if dadosTrat['ph'] == 'None':
            ph = ''

        # Formata o registros em csv
        registroTratado = f"{dadosTrat['id']},\"{dadosTrat['name']}\",{abv},{ibu},{target_fg},{target_og},{ebc},{srm},{ph}\n"
        print('Registro tratado: ', registroTratado)
        
        # Formata o output conforme o esperado
        output_record = {
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': base64.b64encode(registroTratado.encode("utf-8"))
        }

        # Apenda o outuput formatado na list
        output.append(output_record)

    return {'records': output}
