SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a2
    WHERE a2.subject_id = tc.subject_id
      AND a2.hadm_id != tc.hadm_id
      AND a2.admittime > tc.dischtime
      AND a2.admittime <= tc.dischtime + INTERVAL '30 days'
  ) THEN 1 ELSE 0 
END AS readmission_30d;