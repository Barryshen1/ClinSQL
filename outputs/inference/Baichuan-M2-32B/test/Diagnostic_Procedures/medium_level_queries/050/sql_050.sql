LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON hc.hcpcs_cd = dh.code
  WHERE dh.category = 'Diagnostic Imaging';