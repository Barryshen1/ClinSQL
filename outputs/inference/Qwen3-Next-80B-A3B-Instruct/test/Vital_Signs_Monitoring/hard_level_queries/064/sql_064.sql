WITH cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON i.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND (LOWER(d.long_title) LIKE '%acute renal failure%'
         OR LOWER(d.long_title) LIKE '%acute kidney injury%')
),

vitals_48h AS (
  SELECT
    c.stay_id,
    ce.itemid,
    ce.charttime,
    ce.valuenum,
    CASE 
      WHEN ce.itemid = (SELECT itemid FROM physionet-data.mimiciv_3_1_icu.d_items WHERE label = 'Mean Arterial Pressure') AND ce.valuenum < 65 THEN 1
      ELSE 0
    END AS hypotension_event,
    CASE 
      WHEN ce.itemid = (SELECT itemid FROM physionet-data.mimiciv_3_1_icu.d_items WHERE label = 'Heart Rate') AND ce.valuenum > 130 THEN 1
      ELSE 0
    END AS tachycardia_event
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce ON c.stay_id = ce.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (
      SELECT itemid FROM physionet-data.mimiciv_3_1_icu.d_items WHERE label IN ('Mean Arterial Pressure', 'Heart Rate')
    )
),

composite_score AS (
  SELECT
    stay_id,
    SUM(hypotension_event) AS hypotension_count,
    SUM(tachycardia_event) AS tachycardia_count,
    SUM(hypotension_event) + SUM(tachycardia_event) AS composite_score
  FROM vitals_48h
  GROUP BY stay_id
),

percentiles_and_quartiles AS (
  SELECT
    cs.*,
    PERCENTILE_CONT(composite_score, 0.95) OVER () AS p95_composite,
    NTILE(4) OVER (ORDER BY composite_score) AS quartile
  FROM composite_score cs
)

SELECT
  'Top Quartile' AS group_label,
  AVG(hypotension_count) AS avg_hypotension_count,
  AVG(tachycardia_count) AS avg_tachycardia_count,
  AVG(i.los) AS avg_icu_los,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM percentiles_and_quartiles pq
JOIN physionet-data.mimiciv_3_1_icu.icustays i ON pq.stay_id = i.stay_id
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
WHERE quartile = 4

UNION ALL

SELECT
  'Cohort' AS group_label,
  AVG(hypotension_count) AS avg_hypotension_count,
  AVG(tachycardia_count) AS avg_tachycardia_count,
  AVG(i.los) AS avg_icu_los,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM percentiles_and_quartiles pq
JOIN physionet-data.mimiciv_3_1_icu.icustays i ON pq.stay_id = i.stay_id
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id

ORDER BY group_label;