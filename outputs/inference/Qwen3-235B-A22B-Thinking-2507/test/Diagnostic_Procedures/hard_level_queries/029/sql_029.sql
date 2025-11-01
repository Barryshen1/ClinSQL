WITH icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_year_group,
    -- Fix: Use TIMESTAMP() and TIMESTAMP_DIFF() for BigQuery compatibility
    p.anchor_age + TIMESTAMP_DIFF(i.intime, TIMESTAMP(p.anchor_year, 1, 1, 0, 0, 0), YEAR) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + TIMESTAMP_DIFF(i.intime, TIMESTAMP(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 68 AND 78
),
vasopressor_items AS (
  -- Explicit vasopressor item IDs (more reliable than label keywords)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE itemid IN (
    221906, -- Norepinephrine
    221289, -- Epinephrine
    221662, -- Dopamine
    221749, -- Phenylephrine
    222315  -- Vasopressin
  )
),
vasopressor_stays AS (
  SELECT DISTINCT
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON i.stay_id = ie.stay_id
  INNER JOIN vasopressor_items vi
    ON ie.itemid = vi.itemid
  WHERE ie.starttime >= i.intime 
    AND ie.starttime <= i.intime + INTERVAL '72' HOUR
),
lab_counts AS (
  SELECT 
    vs.stay_id,
    COUNT(*) AS lab_count
  FROM vasopressor_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON vs.hadm_id = le.hadm_id 
    AND vs.subject_id = le.subject_id
  WHERE le.charttime >= vs.intime 
    AND le.charttime <= vs.intime + INTERVAL '72' HOUR
  GROUP BY vs.stay_id
),
imaging_counts AS (
  SELECT 
    vs.stay_id,
    COUNT(*) AS imaging_count
  FROM vasopressor_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON vs.hadm_id = p.hadm_id 
    AND vs.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  WHERE p.chartdate >= DATE(vs.intime) 
    AND p.chartdate <= DATE_ADD(vs.intime, INTERVAL 3 DAY)  -- 3-day window
    AND (
      LOWER(d.long_title) LIKE '%x-ray%' 
      OR LOWER(d.long_title) LIKE '%ct%' 
      OR LOWER(d.long_title) LIKE '%mri%' 
      OR LOWER(d.long_title) LIKE '%ultrasound%' 
      OR LOWER(d.long_title) LIKE '%radiology%' 
      OR LOWER(d.long_title) LIKE '%fluoroscopy%'
    )
  GROUP BY vs.stay_id
),
diagnostic_load AS (
  SELECT 
    vs.stay_id,
    COALESCE(lc.lab_count, 0) + COALESCE(ic.imaging_count, 0) AS total_diagnostic
  FROM vasopressor_stays vs
  LEFT JOIN lab_counts lc ON vs.stay_id = lc.stay_id
  LEFT JOIN imaging_counts ic ON vs.stay_id = ic.stay_id
),
procedure_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
admissions_info AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmissions AS (
  SELECT 
    a1.hadm_id,
    1 AS readmit30
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  WHERE a1.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a1.subject_id
        AND a2.admittime > a1.dischtime
        AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
    )
)
SELECT 
  NTILE(4) OVER (ORDER BY dl.total_diagnostic) AS diagnostic_quartile,
  AVG(pc.procedure_count) AS avg_procedure_count,
  AVG(ai.los) AS avg_los,
  AVG(ai.hospital_expire_flag) AS mortality_rate,
  AVG(CASE 
        WHEN ai.hospital_expire_flag = 0 THEN COALESCE(r.readmit30, 0) 
        ELSE NULL 
      END) AS readmission_rate
FROM diagnostic_load dl
LEFT JOIN procedure_counts pc ON dl.hadm_id = pc.hadm_id
LEFT JOIN admissions_info ai ON dl.hadm_id = ai.hadm_id
LEFT JOIN readmissions r ON dl.hadm_id = r.hadm_id
GROUP BY diagnostic_quartile
ORDER BY diagnostic_quartile;