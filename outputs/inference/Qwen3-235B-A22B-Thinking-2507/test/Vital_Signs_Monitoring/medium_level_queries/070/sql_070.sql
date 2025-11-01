WITH patients_stays AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    -- Approximate age at ICU admission (anchor_year + (admission_year - anchor_year))
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 90 AND 100
),
spo2_avg AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    AVG(c.valuenum) AS avg_spo2
  FROM patients_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
    AND c.charttime BETWEEN s.intime AND s.intime + INTERVAL '24' HOUR
    AND c.itemid = 220277  -- SpO2 itemid
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0  -- Valid SpO2 range
  GROUP BY s.stay_id, s.hadm_id
  HAVING COUNT(*) > 0  -- Ensure at least one measurement
),
categorized AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    a.avg_spo2,
    CASE
      WHEN a.avg_spo2 < 90 THEN '<90'
      WHEN a.avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN a.avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      WHEN a.avg_spo2 > 95 THEN '>95'
      ELSE NULL  -- Exclude values in 92-93 gap
    END AS spo2_group
  FROM patients_stays s
  INNER JOIN spo2_avg a
    ON s.stay_id = a.stay_id
  WHERE a.avg_spo2 IS NOT NULL
),
aki_flag AS (
  SELECT
    c.stay_id,
    c.spo2_group,
    c.avg_spo2,
    MAX(CASE WHEN d.icd_code LIKE 'N17%' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_aki
  FROM categorized c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.stay_id, c.spo2_group, c.avg_spo2
)
SELECT
  spo2_group,
  COUNT(*) AS N,
  ROUND(AVG(avg_spo2), 2) AS mean_spo2,
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)] AS median_spo2,
  ROUND(
    APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] - 
    APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)], 
    2
  ) AS iqr_spo2,
  ROUND(SUM(has_aki) / COUNT(*), 4) AS aki_rate
FROM aki_flag
WHERE spo2_group IS NOT NULL  -- Exclude ungrouped stays (e.g., 92-93)
GROUP BY spo2_group
ORDER BY 
  CASE spo2_group
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
  END;