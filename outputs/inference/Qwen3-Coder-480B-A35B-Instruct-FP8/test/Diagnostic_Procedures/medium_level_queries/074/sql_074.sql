WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los AS icu_los
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(dd.long_title) LIKE '%ischemic stroke%'
    AND i.los BETWEEN 1 AND 7
),
imaging_procedures AS (
  SELECT
    c.hadm_id,
    c.stay_id,
    COUNT(*) AS proc_count
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON c.hadm_id = proc.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE
    REGEXP_CONTAINS(UPPER(dp.long_title), r'CT|MRI|ANGIO|ULTRASOUND|ECHOCARDIOGRAM|FLUOROSCOPY')
  GROUP BY
    c.hadm_id, c.stay_id
),
stratified AS (
  SELECT
    c.stay_id,
    CASE
      WHEN c.icu_los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN c.icu_los BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COALESCE(ip.proc_count, 0) AS proc_count
  FROM
    cohort c
  LEFT JOIN
    imaging_procedures ip
    ON c.hadm_id = ip.hadm_id AND c.stay_id = ip.stay_id
)
SELECT
  los_group,
  COUNT(*) AS stay_count,
  AVG(proc_count) AS mean_procedures,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures
FROM
  stratified
GROUP BY
  los_group
ORDER BY
  los_group;