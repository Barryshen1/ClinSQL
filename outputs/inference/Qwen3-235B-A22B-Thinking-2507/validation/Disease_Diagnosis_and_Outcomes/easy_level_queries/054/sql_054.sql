SELECT
  STDDEV(los_days) AS sd_los
FROM (
  SELECT
    adm.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND adm.dischtime IS NOT NULL
) filtered_adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON filtered_adm.hadm_id = diag.hadm_id
WHERE
  filtered_adm.age_at_admission BETWEEN 51 AND 61
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432'))
    OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
  );