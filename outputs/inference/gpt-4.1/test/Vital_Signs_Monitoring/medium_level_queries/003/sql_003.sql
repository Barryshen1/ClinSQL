WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 71 AND 81
),

temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND (LOWER(unitname) LIKE '%celsius%' OR LOWER(unitname) LIKE '%fahrenheit%')
),

temps AS (
  SELECT
    c.stay_id,
    ce.charttime,
    ce.valuenum,
    di.unitname
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
      AND c.hadm_id = ce.hadm_id
      AND c.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE
      ce.itemid IN (SELECT itemid FROM temp_items)
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),

temps_celsius AS (
  SELECT
    stay_id,
    charttime,
    CASE
      WHEN LOWER(unitname) LIKE '%fahrenheit%' THEN (valuenum - 32) * 5.0/9.0
      ELSE valuenum
    END AS temp_celsius
  FROM temps
),

stay_avg_temp AS (
  SELECT
    stay_id,
    AVG(temp_celsius) AS avg_temp
  FROM temps_celsius
  GROUP BY stay_id
),

-- MI diagnosis: ICD-10 I21/I22, ICD-9 410
mi_stays AS (
  SELECT DISTINCT icu.stay_id
  FROM
    cohort icu
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON icu.hadm_id = dx.hadm_id
  WHERE
    (
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
      OR
      (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%'))
    )
),

final AS (
  SELECT
    s.stay_id,
    s.avg_temp,
    CASE
      WHEN s.avg_temp < 36.0 THEN '<36.0'
      WHEN s.avg_temp >= 36.0 AND s.avg_temp < 38.0 THEN '36.0–37.9'
      WHEN s.avg_temp >= 38.0 THEN '≥38.0'
    END AS temp_category,
    CASE WHEN ms.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM
    stay_avg_temp s
    LEFT JOIN mi_stays ms ON s.stay_id = ms.stay_id
)

SELECT
  temp_category,
  COUNT(*) AS n_stays,
  ROUND(AVG(avg_temp), 2) AS mean_avg_temp,
  ROUND(APPROX_QUANTILES(avg_temp, 2)[OFFSET(1)], 2) AS median_avg_temp,
  ROUND(APPROX_QUANTILES(avg_temp, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(avg_temp, 4)[OFFSET(3)], 2) AS iqr_75,
  ROUND(SUM(has_mi) / COUNT(*), 4) AS mi_rate
FROM final
WHERE temp_category IS NOT NULL
GROUP BY temp_category
ORDER BY
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
    ELSE 4
  END;