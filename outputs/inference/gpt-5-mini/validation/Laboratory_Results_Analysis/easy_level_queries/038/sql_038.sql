WITH stroke_admissions AS (
  -- Admissions of male patients with an ischemic stroke diagnosis
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.subject_id = dx.subject_id AND a.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND (
      -- ICD-10 cerebral infarction codes (e.g., I63*) are strongly indicative of ischemic stroke
      (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'I63')
      -- plus text matching on the diagnosis description to capture other encodings
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%ischemic%'
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%ischaemic%'
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%cerebral infarct%'
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%cerebral infarction%'
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%ischemic stroke%'
    )
),

hgb_items AS (
  -- Itemids corresponding to hemoglobin labs (label matching common variants)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%hemoglobin%'
     OR LOWER(label) LIKE '%haemoglobin%'
     OR LOWER(label) LIKE '%hgb%'
),

hgb_per_admission AS (
  -- Minimum hemoglobin within 24 hours of admission for each stroke admission
  SELECT
    s.hadm_id,
    MIN(l.valuenum) AS min_hgb_within_24h,
    COUNT(1) AS n_hgb_measurements
  FROM stroke_admissions s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.hadm_id = l.hadm_id
  JOIN hgb_items hi
    ON l.itemid = hi.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.valuenum > 0
    -- within 24 hours of hospital admission
    AND l.charttime >= s.admittime
    AND l.charttime <= TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
  GROUP BY s.hadm_id
)

-- Final result: overall minimum hemoglobin among male ischemic stroke admissions within 24h
SELECT
  MIN(min_hgb_within_24h) AS overall_min_hgb_g_per_dL,
  COUNT(*) AS n_admissions_with_hgb_within_24h
FROM hgb_per_admission;