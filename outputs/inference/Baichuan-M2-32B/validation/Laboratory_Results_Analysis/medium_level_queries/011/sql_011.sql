WITH patients_with_age AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year <= EXTRACT(YEAR FROM a.admittime)
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 61 AND 71
),
chest_pain_admissions AS (
  SELECT 
    pwa.subject_id,
    pwa.hadm_id,
    pwa.admittime,
    pwa.age
  FROM patients_with_age pwa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON pwa.subject_id = d.subject_id AND pwa.hadm_id = d.hadm_id
  WHERE 
    d.seq_num = 1
    AND (
      (d.icd_version = 10 AND UPPER(d.icd_code) IN ('R07.8', 'R07.9'))
      OR (d.icd_version = 9 AND UPPER(d.icd_code) LIKE '786.5%')
    )
),
hs_tnt_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-TnT%' OR label LIKE '%high-sensitivity Troponin T%'
),
first_hs_tnt_per_admission AS (
  SELECT 
    cpa.subject_id,
    cpa.hadm_id,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY cpa.hadm_id 
      ORDER BY le.charttime, le.labevent_id
    ) AS rn
  FROM chest_pain_admissions cpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cpa.subject_id = le.subject_id AND cpa.hadm_id = le.hadm_id
  WHERE 
    le.itemid IN (SELECT itemid FROM hs_tnt_itemids)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.valuenum >= 0
),
classified_results AS (
  SELECT 
    CASE 
      WHEN valuenum >= ref_range_lower AND valuenum <= ref_range_upper THEN 'normal'
      WHEN valuenum > ref_range_upper AND valuenum < 3 * ref_range_upper THEN 'borderline'
      WHEN valuenum >= 3 * ref_range_upper THEN 'myocardial injury'
      ELSE 'unknown'
    END AS category
  FROM first_hs_tnt_per_admission
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent
FROM classified_results
GROUP BY category
ORDER BY category;