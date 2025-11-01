WITH hf_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic 
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND dic.long_title LIKE '%heart failure%'
  GROUP BY a.hadm_id, a.admittime, a.dischtime
),
ct_mri_counts AS (
  SELECT 
    hadm_id, 
    SUM(ct_count) AS total_ct_mri
  FROM (
    SELECT 
      hadm_id, 
      COUNT(*) AS ct_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
      ON h.hcpcs_cd = d.code
    WHERE 
      d.short_description LIKE '%CT%' 
      OR d.short_description LIKE '%MRI%'
    GROUP BY hadm_id
    
    UNION ALL
    
    SELECT 
      hadm_id, 
      COUNT(*) AS ct_count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
      ON p.itemid = d.itemid
    WHERE 
      d.label LIKE '%CT%' 
      OR d.label LIKE '%MRI%'
    GROUP BY hadm_id
  ) AS combined
  GROUP BY hadm_id
)
SELECT
  ha.diagnosis_type,
  CASE 
    WHEN ha.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    ELSE '4-7 days'
  END AS los_group,
  AVG(COALESCE(cmc.total_ct_mri, 0)) AS mean_ct_mri,
  MIN(COALESCE(cmc.total_ct_mri, 0)) AS min_ct_mri,
  MAX(COALESCE(cmc.total_ct_mri, 0)) AS max_ct_mri
FROM hf_admissions ha
LEFT JOIN ct_mri_counts cmc 
  ON ha.hadm_id = cmc.hadm_id
GROUP BY ha.diagnosis_type, los_group;