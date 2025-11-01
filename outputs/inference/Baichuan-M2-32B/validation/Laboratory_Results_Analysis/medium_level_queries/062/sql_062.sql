WITH 
  hstnt_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%hs-TnT%' OR label LIKE '%high-sensitivity troponin t%'
  ),
  eligible_patients AS (
    SELECT 
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 46 AND 56
      AND a.dischtime IS NOT NULL
  ),
  acs_admissions AS (
    SELECT DISTINCT
      d.subject_id,
      d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_code IN (
      'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
      'I24.0', 'I24.1', 'I24.2', 'I24.3', 'I24.4', 'I24.8', 'I24.9'
    )
      AND d.icd_version = 10
  ),
  first_hstnt AS (
    SELECT 
      le.subject_id,
      le.hadm_id,
      le.valuenum,
      le.ref_range_lower,
      le.ref_range_upper,
      CASE 
        WHEN le.valuenum BETWEEN le.ref_range_lower AND le.ref_range_upper THEN 'Normal'
        WHEN le.valuenum > le.ref_range_upper AND le.valuenum <= (le.ref_range_upper * 1.5) THEN 'Borderline'
        WHEN le.valuenum > (le.ref_range_upper * 1.5) THEN 'Myocardial Injury'
        ELSE NULL
      END AS category
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE le.itemid IN (SELECT itemid FROM hstnt_itemids)
      AND le.valuenum IS NOT NULL
      AND le.ref_range_lower IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
      AND le.hadm_id IN (SELECT hadm_id FROM acs_admissions) -- Filter early for efficiency
    QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
  ),
  combined AS (
    SELECT 
      ep.subject_id,
      ep.hadm_id,
      (TIMESTAMP_DIFF(ep.dischtime, ep.admittime, SECOND) / 86400.0) AS los_days,
      fhstnt.category
    FROM eligible_patients ep
    INNER JOIN acs_admissions aa 
      ON ep.subject_id = aa.subject_id AND ep.hadm_id = aa.hadm_id
    INNER JOIN first_hstnt fhstnt 
      ON ep.hadm_id = fhstnt.hadm_id
  )
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM combined), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM combined
GROUP BY category
ORDER BY category;