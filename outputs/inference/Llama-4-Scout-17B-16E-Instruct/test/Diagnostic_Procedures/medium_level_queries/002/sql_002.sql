WITH 
-- Identify TIA patients
tia_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    a.admittime, 
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 64 AND 74
    AND dd.long_title LIKE '%Transient ischemic attack%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Identify ICU stays
icu_stays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    1 AS in_icu
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Identify ultrasounds/echocardiograms
echo_us AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_procedures
  FROM 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE 
    hcpcs_cd IN (
      -- CPT codes for echocardiogram and ultrasound
      '93307', '93308', '93350', '76770', '76775', '76870', '76872'
    )
  GROUP BY 
    hadm_id
)

-- Main query
SELECT 
  CASE 
    WHEN TIMESTAMP_DIFF(tp.dischtime, tp.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN TIMESTAMP_DIFF(tp.dischtime, tp.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  COALESCE(icu.in_icu, 0) AS in_icu,
  AVG(echo_us.num_procedures) AS mean_procedures
FROM 
  tia_patients tp
  LEFT JOIN icu_stays icu ON tp.hadm_id = icu.hadm_id
  LEFT JOIN echo_us ON tp.hadm_id = echo_us.hadm_id
GROUP BY 
  los_group, 
  in_icu
ORDER BY 
  los_group, 
  in_icu;