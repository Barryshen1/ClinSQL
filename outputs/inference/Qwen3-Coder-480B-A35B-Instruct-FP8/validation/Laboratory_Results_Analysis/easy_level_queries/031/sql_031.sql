SELECT
  APPROX_QUANTILES(lab.valuenum, 100)[OFFSET(75)] AS potassium_75th_percentile
FROM
  physionet-data.mimiciv_3_1_icu.icustays icu
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON icu.hadm_id = adm.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.patients pat
  ON icu.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents lab
  ON icu.hadm_id = lab.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems dlab
  ON lab.itemid = dlab.itemid
WHERE
  pat.gender = 'M'
  AND dlab.label = 'potassium'
  AND dlab.fluid = 'blood'
  AND DATE(lab.charttime) = DATE(adm.dischtime)
  AND lab.valuenum IS NOT NULL;