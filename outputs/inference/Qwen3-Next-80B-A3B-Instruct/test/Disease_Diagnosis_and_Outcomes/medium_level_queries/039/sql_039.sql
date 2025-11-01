WITH amipatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.gender,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND (
      dicd.long_title LIKE '%acute myocardial infarction%'
      OR d.icd_code LIKE '410%'
      OR d.icd_code LIKE 'I21%'
      OR d.icd_code LIKE 'I22%'
      OR d.icd_code LIKE 'I23%'
    )
),
classified AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '>=8 days'
      ELSE 'Unknown'
    END AS los_category,
    CASE
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-emergent'
    END AS admission_category
  FROM
    amipatients
  WHERE
    los_days IS NOT NULL
)
SELECT
  los_category,
  admission_category,
  ROUND(
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS in_hospital_mortality_percent,
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, DAY) END, 
    2
  )[OFFSET(1)] AS median_time_to_death_days
FROM
  classified
WHERE
  los_category != 'Unknown'
GROUP BY
  los_category,
  admission_category
ORDER BY
  los_category,
  admission_category;