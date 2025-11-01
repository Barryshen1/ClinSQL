WITH target_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    p.anchor_age, 
    p.anchor_year, 
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admittime IS NOT NULL 
    AND a.dischtime IS NOT NULL
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E08' AND 'E13')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
medication_flags AS (
  SELECT
    a.hadm_id,
    MAX(CASE 
      WHEN p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR 
        AND p.drug LIKE '%Insulin%' 
      THEN 1 ELSE 0 
    END) AS insulin_0_48,
    MAX(CASE 
      WHEN p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR 
        AND p.route IN ('Oral', 'PO') 
        AND p.drug NOT LIKE '%Insulin%' 
      THEN 1 ELSE 0 
    END) AS oral_0_48,
    MAX(CASE 
      WHEN p.starttime BETWEEN a.dischtime - INTERVAL 72 HOUR AND a.dischtime 
        AND p.drug LIKE '%Insulin%' 
      THEN 1 ELSE 0 
    END) AS insulin_final,
    MAX(CASE 
      WHEN p.starttime BETWEEN a.dischtime - INTERVAL 72 HOUR AND a.dischtime 
        AND p.route IN ('Oral', 'PO') 
        AND p.drug NOT LIKE '%Insulin%' 
      THEN 1 ELSE 0 
    END) AS oral_final
  FROM target_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
)
SELECT
  AVG(insulin_0_48) AS insulin_rate_0_48,
  AVG(oral_0_48) AS oral_rate_0_48,
  AVG(insulin_final) AS insulin_rate_final,
  AVG(oral_final) AS oral_rate_final,
  (AVG(insulin_final) - AVG(insulin_0_48)) AS insulin_net_change,
  (AVG(oral_final) - AVG(oral_0_48)) AS oral_net_change
FROM medication_flags;