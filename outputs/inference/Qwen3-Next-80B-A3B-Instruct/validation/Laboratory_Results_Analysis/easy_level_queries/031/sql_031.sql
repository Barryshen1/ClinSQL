SELECT APPROX_QUANTILES(lab.valuenum, 100)[OFFSET(75)] AS p75_serum_potassium
FROM physionet-data.mimiciv_3_1_hosp.patients p
INNER JOIN physionet-data.mimiciv_3_1_icu.icustays icu
  ON p.subject_id = icu.subject_id
INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
  ON icu.hadm_id = adm.hadm_id
INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents lab
  ON p.subject_id = lab.subject_id AND adm.hadm_id = lab.hadm_id
INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d_lab
  ON lab.itemid = d_lab.itemid
WHERE p.gender = 'M'
  AND d_lab.label IN ('Potassium', 'Serum Potassium', 'K+', 'Potassium, Serum')
  AND lab.valuenum IS NOT NULL
  AND DATE(lab.charttime) = DATE(adm.dischtime);