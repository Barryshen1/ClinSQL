WITH 
-- Step 1: Identify women 74-84 with ICH
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- Calculate age at admission (anchor_year is last record year)
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 74 AND 84
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432')
          OR (d.icd_version = 10 AND d.icd_code >= 'I60' AND d.icd_code < 'I63')
        )
    )
),

-- Step 2: Find distinct abnormal labs in first 72 hours
abnormal_labs AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    l.itemid
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = l.hadm_id
  WHERE 
    l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL  -- Numeric values only
    AND (
      (l.valuenum < l.ref_range_lower AND l.ref_range_lower IS NOT NULL)
      OR (l.valuenum > l.ref_range_upper AND l.ref_range_upper IS NOT NULL)
    )
  GROUP BY c.subject_id, c.hadm_id, l.itemid  -- Distinct labs per patient
),

-- Step 3: Compute instability metric (count of distinct abnormal labs)
instability AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT itemid) AS instability_count
  FROM abnormal_labs
  GROUP BY subject_id, hadm_id
),

-- Step 4: Assign quintiles to cohort
cohort_quintiles AS (
  SELECT 
    c.*,
    COALESCE(i.instability_count, 0) AS instability_count,
    NTILE(5) OVER (ORDER BY COALESCE(i.instability_count, 0)) AS quintile
  FROM cohort c
  LEFT JOIN instability i
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id
)

-- Step 5: Report mortality and mean LOS by quintile
SELECT 
  quintile,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days
FROM cohort_quintiles
GROUP BY quintile
ORDER BY quintile;