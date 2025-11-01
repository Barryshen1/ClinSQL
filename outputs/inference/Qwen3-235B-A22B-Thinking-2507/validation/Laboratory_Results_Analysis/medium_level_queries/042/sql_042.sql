WITH chest_pain_admissions AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'R07%')  -- ICD-10 chest pain codes
          OR (d.icd_version = 9 AND d.icd_code LIKE '7865%')  -- ICD-9 chest pain codes
        )
    )
),
filtered_admissions AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM chest_pain_admissions
  WHERE 
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 84 AND 94
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime, l.labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.hadm_id IN (SELECT hadm_id FROM filtered_admissions)
    AND l.itemid IN (50354, 50355)  -- Troponin T item IDs
    AND l.valueuom = 'ng/mL'        -- Standard unit
    AND l.valuenum IS NOT NULL      -- Numeric values only
)
SELECT
  CASE 
    WHEN valuenum < 0.014 THEN 'normal'
    WHEN valuenum < 0.059 THEN 'borderline'
    ELSE 'elevated'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM filtered_admissions f
INNER JOIN first_troponin t
  ON f.hadm_id = t.hadm_id
WHERE t.rn = 1  -- First troponin measurement
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;