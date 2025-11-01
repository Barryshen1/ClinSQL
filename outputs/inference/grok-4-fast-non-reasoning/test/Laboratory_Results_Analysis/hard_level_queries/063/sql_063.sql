WITH cohort AS (
  -- Female patients aged 53-63 with primary PE admission (first per patient)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I26%'
    AND d.seq_num = CAST(1 AS INT64)
),

filtered_cohort AS (
  SELECT * FROM cohort WHERE rn = 1
),

labs AS (
  -- 72-hour labs for instability markers (with category filter)
  SELECT 
    fc.subject_id,
    fc.hadm_id,
    fc.admittime,
    le.charttime,
    le.itemid,
    le.valuenum,
    le.valueuom,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON fc.subject_id = le.subject_id AND fc.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE le.charttime >= fc.admittime 
    AND le.charttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 3 DAY)
    AND le.valuenum IS NOT NULL
    AND dli.category IN ('Blood Gases', 'Chemistry', 'Hematology')
    AND le.itemid IN (
      50868,  -- pH (arterial)
      51237,  -- Lactate
      50912,  -- Creatinine
      5131,   -- WBC (corrected)
      51222,  -- Hgb
      51244,  -- Platelets (corrected)
      50983,  -- Sodium
      50971,  -- Potassium
      50809,  -- Glucose
      51249   -- INR (corrected; PT/INR related, standard is 51249 for INR)
    )
),

instability AS (
  -- Compute per-patient instability score (average max deviation per lab type)
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT itemid) AS num_labs,
    AVG(max_deviation) AS instability_score  -- Average deviation (normalized)
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      itemid,
      MAX(
        CASE 
          WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL 
          THEN ABS(valuenum - (ref_range_lower + ref_range_upper)/2.0)
          ELSE ABS(valuenum - 100.0)  -- Better default mid-point placeholder (e.g., for labs around 100)
        END
      ) AS max_deviation
    FROM labs
    GROUP BY subject_id, hadm_id, itemid
  ) sub
  GROUP BY subject_id, hadm_id
  HAVING num_labs >= 3  -- Require multiple labs for reliability
),

threshold AS (
  SELECT 
    PERCENTILE_CONT(0.75, instability_score) AS thresh_75
  FROM instability
),

high_risk AS (
  SELECT 
    i.*,
    fc.dischtime,
    fc.deathtime,
    fc.admittime,
    t.thresh_75,
    CASE WHEN i.instability_score >= t.thresh_75 THEN 1 ELSE 0 END AS high_risk_flag,
    -- Critical lab: abnormal flag or extreme deviation
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM labs l 
        WHERE l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id 
          AND (l.flag = 'abnormal' OR 
               (l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL AND 
                ABS(l.valuenum - (l.ref_range_lower + l.ref_range_upper)/2.0) > 0.2 * ((l.ref_range_upper - l.ref_range_lower)/2.0)))
      ) THEN 1 ELSE 0 
    END AS has_critical_lab
  FROM instability i
  INNER JOIN filtered_cohort fc ON i.subject_id = fc.subject_id AND i.hadm_id = fc.hadm_id
  CROSS JOIN threshold t
),

all_inpatient_critical_rate AS (
  -- Pre-aggregate critical rate for all female inpatients 53-63
  SELECT 
    AVG(has_critical_lab_all * 1.0) * 100 AS all_inpatient_critical_rate_pct
  FROM (
    SELECT 
      p.subject_id,
      a.hadm_id,
      CASE 
        WHEN EXISTS (
          SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
          INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
          WHERE le.subject_id = p.subject_id AND le.hadm_id = a.hadm_id
            AND le.charttime >= a.admittime AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 3 DAY)
            AND le.valuenum IS NOT NULL
            AND dli.category IN ('Blood Gases', 'Chemistry', 'Hematology')
            AND le.flag = 'abnormal'
        ) THEN 1 ELSE 0 
      END AS has_critical_lab_all
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 53 AND 63
  ) sub
)

SELECT 
  t.thresh_75,
  -- Mortality % for high-risk (in-hospital)
  AVG(CASE WHEN hr.high_risk_flag = 1 AND hr.deathtime IS NOT NULL THEN 1.0 ELSE 0 END) * 100 AS mortality_pct,
  -- Mean LOS for high-risk
  AVG(CASE WHEN hr.high_risk_flag = 1 
    THEN DATETIME_DIFF(hr.dischtime, hr.admittime, HOUR) / 24.0 
    ELSE NULL END) AS mean_los_days,
  -- Critical rate for high-risk PE cohort
  AVG(CASE WHEN hr.high_risk_flag = 1 THEN hr.has_critical_lab * 1.0 ELSE NULL END) * 100 AS high_risk_critical_rate_pct,
  -- Critical rate for all inpatients
  air.all_inpatient_critical_rate_pct
FROM high_risk hr
CROSS JOIN threshold t
CROSS JOIN all_inpatient_critical_rate air
WHERE hr.high_risk_flag = 1  -- Focus on high-risk only for metrics
GROUP BY t.thresh_75, air.all_inpatient_critical_rate_pct;