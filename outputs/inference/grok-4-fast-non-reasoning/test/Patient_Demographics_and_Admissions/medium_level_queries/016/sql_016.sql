WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Check for any ICU transfer to exclude non-general ward stays
    CASE WHEN COUNTIF(t.careunit LIKE 'ICU%') > 0 THEN 1 ELSE 0 END AS has_icu_stay
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.subject_id = t.subject_id 
    AND a.hadm_id = t.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type != 'ICU'  -- Exclude direct ICU admissions
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag IN (0, 1)
    AND EXTRACT(YEAR FROM a.admittime) >= 2008  -- Align with data availability
  GROUP BY 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, 
    a.discharge_location, p.gender, p.anchor_age
  HAVING 
    has_icu_stay = 0  -- Only general ward stays (no ICU transfers)
),
discharge_strata AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location IN ('HOSPICE', 'Hospice') THEN 'HOSPICE'
      WHEN discharge_location IN ('HOME', 'Disch to home', 'SNF', 'REHAB/DISTINCT PART HOSP') THEN 'HOME'
      ELSE 'OTHER'
    END AS discharge_category
  FROM cohort
)
SELECT 
  discharge_category,
  -- LOS percentiles
  PERCENTILE_CONT(los_days, 0.5) WITHIN GROUP (ORDER BY los_days) AS p50_los,
  PERCENTILE_CONT(los_days, 0.75) WITHIN GROUP (ORDER BY los_days) AS p75_los,
  PERCENTILE_CONT(los_days, 0.9) WITHIN GROUP (ORDER BY los_days) AS p90_los,
  PERCENTILE_CONT(los_days, 0.95) WITHIN GROUP (ORDER BY los_days) AS p95_los,
  -- Percentile rank of a 7-day stay (% of stays <= 7 days)
  (COUNTIF(los_days <= 7) * 100.0 / COUNT(*)) AS p7day_rank_percent
FROM discharge_strata
WHERE discharge_category IN ('HOME', 'HOSPICE', 'DEATH')
GROUP BY discharge_category
ORDER BY 
  CASE discharge_category 
    WHEN 'HOME' THEN 1 
    WHEN 'HOSPICE' THEN 2 
    WHEN 'DEATH' THEN 3 
  END;