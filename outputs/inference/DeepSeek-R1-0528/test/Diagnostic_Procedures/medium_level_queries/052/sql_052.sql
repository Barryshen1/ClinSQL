WITH trauma_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
      ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE 
      LOWER(d.long_title) LIKE '%trauma%' OR 
      LOWER(d.long_title) LIKE '%multiple trauma%' OR 
      LOWER(d.long_title) LIKE '%multiple injuries%' OR 
      LOWER(d.long_title) LIKE '%polytrauma%'
),

ultrasound_agg AS (
  SELECT hadm_id, COUNT(*) AS total_ultrasound_count
  FROM (
    -- ICD Procedures (ultrasound/echocardiography)
    SELECT proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
        ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
    WHERE 
        LOWER(dp.long_title) LIKE '%ultrasound%' OR 
        LOWER(dp.long_title) LIKE '%echocardiography%'

    UNION ALL

    -- HCPCS Events (ultrasound/echocardiography)
    SELECT hcpc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
        ON hcpc.hcpcs_cd = dh.code
    WHERE 
        LOWER(dh.short_description) LIKE '%ultrasound%' OR 
        LOWER(dh.short_description) LIKE '%echocardiography%' OR
        LOWER(dh.long_description) LIKE '%ultrasound%' OR 
        LOWER(dh.long_description) LIKE '%echocardiography%'
  ) t
  GROUP BY hadm_id
),

icu_days AS (
  SELECT 
      hadm_id, 
      SUM(los) AS total_icu_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
)

SELECT 
    adm.admission_type,
    CASE 
        WHEN icu.total_icu_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN icu.total_icu_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS icu_stay_category,
    AVG(COALESCE(u.total_ultrasound_count, 0)) AS mean_ultrasounds,
    MIN(COALESCE(u.total_ultrasound_count, 0)) AS min_ultrasounds,
    MAX(COALESCE(u.total_ultrasound_count, 0)) AS max_ultrasounds
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON adm.subject_id = pat.subject_id
INNER JOIN trauma_admissions tr 
    ON adm.hadm_id = tr.hadm_id
INNER JOIN icu_days icu 
    ON adm.hadm_id = icu.hadm_id
LEFT JOIN ultrasound_agg u 
    ON adm.hadm_id = u.hadm_id
WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND adm.admission_type IN ('EMERGENCY', 'ELECTIVE')
GROUP BY adm.admission_type, icu_stay_category
HAVING icu_stay_category IS NOT NULL;