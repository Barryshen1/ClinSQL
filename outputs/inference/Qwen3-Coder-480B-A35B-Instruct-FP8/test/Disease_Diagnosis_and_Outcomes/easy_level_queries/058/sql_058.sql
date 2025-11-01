SELECT
  APPROX_QUANTILES(
    DATETIME_DIFF(dischtime, admittime, HOUR), 100
  )[OFFSET(75)] AS percentile_75_los_hours
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 37 AND 47
  AND d.seq_num = 1
  AND (
    LOWER(dd.long_title) LIKE '%hemorrhagic stroke%'
    OR LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
  );