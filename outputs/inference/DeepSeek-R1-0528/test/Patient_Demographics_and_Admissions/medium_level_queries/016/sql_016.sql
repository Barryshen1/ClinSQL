WITH cohort AS (
  SELECT
    adm.hadm_id,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'death'
      WHEN adm.discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN adm.discharge_location = 'HOME' THEN 'home'
      ELSE 'other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pat.gender = 'M'
    AND icu.stay_id IS NULL  -- Exclude any ICU stays
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year))
        BETWEEN 44 AND 54   -- Age 44-54 at admission
),
filtered_cohort AS (
  SELECT
    hadm_id,
    los,
    discharge_category
  FROM
    cohort
  WHERE
    discharge_category IN ('home', 'hospice', 'death')  -- Only these categories
)

SELECT
  discharge_category,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  ROUND(COUNTIF(los <= 7) * 100.0 / COUNT(*), 2) AS percentile_rank_7day
FROM
  filtered_cohort
GROUP BY
  discharge_category
ORDER BY
  discharge_category;