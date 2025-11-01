WITH cabg_icd_codes AS (
  -- List of CABG ICD-9 codes (36.10–36.19)
  SELECT '36.10' AS icd_code UNION ALL
  SELECT '36.11' UNION ALL
  SELECT '36.12' UNION ALL
  SELECT '36.13' UNION ALL
  SELECT '36.14' UNION ALL
  SELECT '36.15' UNION ALL
  SELECT '36.16' UNION ALL
  SELECT '36.17' UNION ALL
  SELECT '36.19'
),
first_admissions AS (
  -- Get first admission for each patient
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN (
      SELECT
        subject_id,
        MIN(admittime) AS first_admittime
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
      GROUP BY subject_id
    ) fa
      ON p.subject_id = fa.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON a.subject_id = fa.subject_id AND a.admittime = fa.first_admittime
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
cabg_patients AS (
  -- Patients whose first admission had CABG
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON fa.subject_id = pi.subject_id AND fa.hadm_id = pi.hadm_id
    JOIN cabg_icd_codes c
      ON pi.icd_code = c.icd_code AND pi.icd_version = 9
)
SELECT
  APPROX_QUANTILES(hospital_expire_flag, 4)[OFFSET(1)] AS mortality_25th_percentile,
  COUNT(*) AS cohort_size,
  SUM(hospital_expire_flag) AS deaths
FROM
  cabg_patients
;