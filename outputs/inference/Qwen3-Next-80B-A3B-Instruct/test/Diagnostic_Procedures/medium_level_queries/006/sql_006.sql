WITH sepsis_cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('99592') OR d.icd_code LIKE '038%')
      OR
      (d.icd_version = 10 AND d.icd_code IN ('A419', 'R6520', 'R6521'))
    )
    AND a.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
      WHERE (icd_version = 10 AND icd_code = 'R6522')
         OR (icd_version = 9 AND icd_code = '78552')
    )
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM (
    -- ICU procedureevents with ultrasound label
    SELECT p.hadm_id
    FROM physionet-data.mimiciv_3_1_icu.procedureevents p
    JOIN physionet-data.mimiciv_3_1_icu.d_items d ON p.itemid = d.itemid
    WHERE LOWER(d.label) LIKE '%ultrasound%'
    
    UNION ALL
    
    -- HOSP hcpcsevents with ultrasound description
    SELECT h.hadm_id
    FROM physionet-data.mimiciv_3_1_hosp.hcpcsevents h
    JOIN physionet-data.mimiciv_3_1_hosp.d_hcpcs dh ON h.hcpcs_cd = dh.code
    WHERE LOWER(dh.short_description) LIKE '%ultrasound%'
  ) AS combined_ultrasounds
  GROUP BY hadm_id
),
cohort_with_icu AS (
  SELECT 
    s.hadm_id,
    s.los_group,
    CASE WHEN i.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_icu_stay
  FROM sepsis_cohort s
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i ON s.hadm_id = i.hadm_id
)
SELECT
  c.los_group,
  c.has_icu_stay,
  COUNT(*) AS patient_count,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM cohort_with_icu c
LEFT JOIN ultrasound_counts u ON c.hadm_id = u.hadm_id
WHERE c.los_group IS NOT NULL
GROUP BY c.los_group, c.has_icu_stay
ORDER BY c.los_group, c.has_icu_stay;