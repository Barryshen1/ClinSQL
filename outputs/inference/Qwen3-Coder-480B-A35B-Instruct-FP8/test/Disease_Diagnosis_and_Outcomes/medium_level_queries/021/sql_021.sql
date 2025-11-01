WITH postop_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE
      WHEN i.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN drg.drg_severity IS NOT NULL THEN drg.drg_severity
      ELSE 0
    END AS charlson_proxy
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
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.drgcodes drg
    ON a.hadm_id = drg.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '997%')
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^T8[0-9]'))
    )
),

grouped_data AS (
  SELECT
    icu_status,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE '<1'
    END AS los_group,
    CASE
      WHEN charlson_proxy <= 3 THEN '<=3'
      WHEN charlson_proxy BETWEEN 4 AND 5 THEN '4-5'
      WHEN charlson_proxy > 5 THEN '>5'
      ELSE 'Unknown'
    END AS charlson_group,
    hospital_expire_flag,
    CASE
      WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admittime, HOUR)
      ELSE NULL
    END AS time_to_death_hours
  FROM
    postop_admissions
)

SELECT
  icu_status,
  los_group,
  charlson_group,
  COUNT(*) AS n,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_percent,
  APPROX_QUANTILES(time_to_death_hours, 2)[OFFSET(1)] AS median_time_to_death_hours
FROM
  grouped_data
GROUP BY
  icu_status,
  los_group,
  charlson_group
ORDER BY
  icu_status,
  los_group,
  charlson_group;