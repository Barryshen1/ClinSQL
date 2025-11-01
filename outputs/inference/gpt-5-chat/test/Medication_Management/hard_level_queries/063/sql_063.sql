WITH pneumonia_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
    AND UPPER(d.long_title) LIKE '%PNEUMONIA%'
),
first24h_meds AS (
  SELECT
    pna.subject_id,
    pna.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity,
    COUNTIF(
      REGEXP_CONTAINS(LOWER(pr.drug), r'(sertraline|fluoxetine|paroxetine|citalopram|escitalopram|venlafaxine|duloxetine|trazodone|linezolid|triptan|buspirone)')
    ) > 0 AS serotonergic_flag
  FROM pneumonia_admissions pna
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pna.hadm_id = pr.hadm_id
  WHERE pr.starttime >= pna.admittime
    AND pr.starttime < DATETIME_ADD(pna.admittime, INTERVAL 24 HOUR)
  GROUP BY pna.subject_id, pna.hadm_id
),
icu_flags AS (
  SELECT DISTINCT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort AS (
  SELECT
    pna.subject_id,
    pna.hadm_id,
    pna.admittime,
    pna.dischtime,
    DATETIME_DIFF(pna.dischtime, pna.admittime, DAY) AS los_days,
    pna.hospital_expire_flag,
    f24.med_complexity,
    f24.serotonergic_flag,
    IFNULL(icu.icu_flag, 0) AS icu_flag
  FROM pneumonia_admissions pna
  JOIN first24h_meds f24
    ON pna.hadm_id = f24.hadm_id
  LEFT JOIN icu_flags icu
    ON pna.hadm_id = icu.hadm_id
),
complexity_stats AS (
  SELECT
    APPROX_QUANTILES(med_complexity, 100)[OFFSET(25)] AS p25_complexity,
    APPROX_QUANTILES(med_complexity, 100)[OFFSET(50)] AS p50_complexity,
    APPROX_QUANTILES(med_complexity, 100)[OFFSET(75)] AS p75_complexity,
    AVG(med_complexity) AS mean_complexity
  FROM cohort
),
los_mortality_by_group AS (
  SELECT
    CASE
      WHEN serotonergic_flag = TRUE THEN 'Serotonergic Risk'
      WHEN icu_flag = 1 THEN 'ICU Patient'
      ELSE 'Other'
    END AS group_label,
    AVG(los_days) AS avg_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort
  WHERE serotonergic_flag = TRUE OR icu_flag = 1
  GROUP BY group_label
),
top_quartile_mortality AS (
  SELECT
    lg.group_label,
    COUNTIF(los_days >= lg.los_p75_days) AS top_quartile_count,
    COUNTIF(los_days >= lg.los_p75_days AND hospital_expire_flag = 1) AS top_quartile_deaths,
    SAFE_DIVIDE(
      COUNTIF(los_days >= lg.los_p75_days AND hospital_expire_flag = 1),
      COUNTIF(los_days >= lg.los_p75_days)
    ) AS top_quartile_mortality_rate
  FROM cohort c
  JOIN los_mortality_by_group lg
    ON (CASE
        WHEN c.serotonergic_flag = TRUE THEN 'Serotonergic Risk'
        WHEN c.icu_flag = 1 THEN 'ICU Patient'
        ELSE 'Other'
      END) = lg.group_label
  WHERE lg.group_label IN ('Serotonergic Risk','ICU Patient')
  GROUP BY lg.group_label, lg.los_p75_days
)
-- Final unified output with consistent schema
SELECT
  'Medication Complexity Stats' AS section,
  NULL AS group_label,
  CAST(p25_complexity AS FLOAT64) AS p25_complexity,
  CAST(p50_complexity AS FLOAT64) AS p50_complexity,
  CAST(p75_complexity AS FLOAT64) AS p75_complexity,
  CAST(mean_complexity AS FLOAT64) AS mean_complexity,
  NULL AS avg_los_days,
  NULL AS los_p75_days,
  NULL AS mortality_rate,
  NULL AS top_quartile_count,
  NULL AS top_quartile_mortality_rate
FROM complexity_stats
UNION ALL
SELECT
  'LOS & Mortality by Group' AS section,
  group_label,
  NULL, NULL, NULL, NULL,
  CAST(avg_los_days AS FLOAT64),
  CAST(los_p75_days AS FLOAT64),
  CAST(mortality_rate AS FLOAT64),
  NULL,
  NULL
FROM los_mortality_by_group
UNION ALL
SELECT
  'Top Quartile LOS & Mortality' AS section,
  group_label,
  NULL, NULL, NULL, NULL,
  NULL, NULL, NULL,
  CAST(top_quartile_count AS INT64),
  CAST(top_quartile_mortality_rate AS FLOAT64)
FROM top_quartile_mortality;