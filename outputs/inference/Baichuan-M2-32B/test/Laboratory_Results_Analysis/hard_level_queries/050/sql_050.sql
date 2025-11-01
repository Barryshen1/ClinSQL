WITH
  -- Eligible ARDS admissions (female, age 40-50, with J80 diagnosis)
  ards_admissions AS (
    SELECT 
      p.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime, 
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 40 AND 50
      AND d.icd_code = 'J80'
      AND d.icd_version = 10
  ),
  -- First ICU stay per ARDS admission (per hadm_id)
  ards_icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM ards_admissions)
  ),
  -- Critical lab events for ARDS ICU stays in first 72h
  ards_lab_events AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.stay_id,
      a.intime,
      l.labevent_id,
      l.itemid,
      l.charttime,
      l.valuenum,
      li.ref_range_lower,
      li.ref_range_upper
    FROM ards_icu_stays a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.subject_id = l.subject_id
      AND a.hadm_id = l.hadm_id
      -- Removed stay_id join because labevents doesn't have stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON l.itemid = li.itemid
    WHERE 
      a.rn = 1
      AND l.charttime >= a.intime
      AND l.charttime <= TIMESTAMP_ADD(a.intime, INTERVAL 72 HOUR)  -- Fixed interval syntax
      AND l.valuenum IS NOT NULL
      AND li.ref_range_lower IS NOT NULL
      AND li.ref_range_upper IS NOT NULL
      AND (l.valuenum < li.ref_range_lower OR l.valuenum > li.ref_range_upper)
  ),
  -- Count per ICU stay
  ards_lab_counts AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      COUNT(*) AS critical_lab_count
    FROM ards_lab_events
    GROUP BY subject_id, hadm_id, stay_id
  ),
  -- 75th percentile
  ards_percentile AS (
    SELECT 
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY critical_lab_count) AS p75
    FROM ards_lab_counts
  ),
  -- Group A: ARDS patients above threshold
  group_a AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.hospital_expire_flag,
      DATEDIFF(a.dischtime, a.admittime) AS los_days,
      COALESCE(c.critical_lab_count, 0) AS critical_lab_count
    FROM ards_admissions a
    INNER JOIN ards_icu_stays i 
      ON a.hadm_id = i.hadm_id AND i.rn = 1
    LEFT JOIN ards_lab_counts c 
      ON a.hadm_id = c.hadm_id AND i.stay_id = c.stay_id
    CROSS JOIN ards_percentile p
    WHERE 
      COALESCE(c.critical_lab_count, 0) >= p.p75
  ),
  -- Now for non-ARDS group: admissions without ARDS diagnosis
  non_ards_admissions AS (
    SELECT 
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 40 AND 50
      AND a.hadm_id NOT IN (
        SELECT hadm_id 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
        WHERE icd_code = 'J80' AND icd_version = 10
      )
  ),
  -- First ICU stay per non-ARDS admission
  non_ards_icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM non_ards_admissions)
  ),
  -- Critical lab events for non-ARDS ICU stays in first 72h
  non_ards_lab_events AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.stay_id,
      a.intime,
      l.labevent_id,
      l.itemid,
      l.charttime,
      l.valuenum,
      li.ref_range_lower,
      li.ref_range_upper
    FROM non_ards_icu_stays a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.subject_id = l.subject_id
      AND a.hadm_id = l.hadm_id
      -- Removed stay_id join because labevents doesn't have stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON l.itemid = li.itemid
    WHERE 
      a.rn = 1
      AND l.charttime >= a.intime
      AND l.charttime <= TIMESTAMP_ADD(a.intime, INTERVAL 72 HOUR)  -- Fixed interval syntax
      AND l.valuenum IS NOT NULL
      AND li.ref_range_lower IS NOT NULL
      AND li.ref_range_upper IS NOT NULL
      AND (l.valuenum < li.ref_range_lower OR l.valuenum > li.ref_range_upper)
  ),
  -- Count per ICU stay
  non_ards_lab_counts AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      COUNT(*) AS critical_lab_count
    FROM non_ards_lab_events
    GROUP BY subject_id, hadm_id, stay_id
  ),
  -- For non-ARDS, we want the average critical_lab_count per ICU stay (for the first ICU stay per admission)
  non_ards_avg AS (
    SELECT 
      AVG(COALESCE(c.critical_lab_count, 0)) AS mean_critical_labs
    FROM non_ards_icu_stays i
    LEFT JOIN non_ards_lab_counts c 
      ON i.hadm_id = c.hadm_id AND i.stay_id = c.stay_id
    WHERE i.rn = 1
  )

-- Now, output for Group A and Group B
SELECT 
  'ARDS_above_threshold' AS group_type,
  AVG(hospital_expire_flag) AS mortality,  -- proportion
  AVG(los_days) AS mean_los,
  AVG(critical_lab_count) AS mean_critical_labs
FROM group_a

UNION ALL

SELECT 
  'non_ards' AS group_type,
  NULL AS mortality,
  NULL AS mean_los,
  mean_critical_labs
FROM non_ards_avg;