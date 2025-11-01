LEFT JOIN physionet-data.mimiciv_3_1_hosp.hcpcsevents hc
  ON vc.hadm_id = hc.hadm_id
  AND hc.chartdate >= DATE(vc.intime)
  AND hc.chartdate <= DATE(vc.intime + INTERVAL '72' HOUR)
LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_hcpcs dh
  ON hc.hcpcs_cd = dh.code
  AND LOWER(dh.short_description) LIKE ANY (ARRAY['%x-ray%', '%ct%', '%mri%', '%ultrasound%', '%fluoroscopy%', '%scan%', '%imaging%']);