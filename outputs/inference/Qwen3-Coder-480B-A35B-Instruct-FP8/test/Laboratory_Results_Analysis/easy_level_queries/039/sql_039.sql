SELECT
  STDDEV_SAMP(max_creatinine) AS std_dev_peak_creatinine
FROM (
  SELECT
    a.hadm_id,
    MAX(le.valuenum) AS max_creatinine
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON a.hadm_id = le.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE
    p.gender = 'M'
    AND LOWER(d.long_title) LIKE '%pneumonia%'
    AND LOWER(dl.label) = 'creatinine'
    AND LOWER(dl.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
  GROUP BY
    a.hadm_id
) AS peak_creatinine_per_admission;