WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '1-3'
      ELSE '4-7'
    END AS los_group,
    CASE 
      WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) THEN 1 
      ELSE 0 
    END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_code IN ('G45.9', '435.9')
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
proc_counts AS (
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    COUNT(*) AS cnt
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pr.icd_code = dip.icd_code 
    AND pr.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ultrasound%'
     OR LOWER(dip.long_title) LIKE '%echocardiography%'
     OR LOWER(dip.long_title) LIKE '%echocardiogram%'
  GROUP BY pr.subject_id, pr.hadm_id
)
SELECT 
  los_group,
  icu_use,
  AVG(COALESCE(pc.cnt, 0)) AS mean_procs_per_admission,
  COUNT(*) AS num_admissions
FROM cohort c
LEFT JOIN proc_counts pc 
  ON pc.subject_id = c.subject_id 
  AND pc.hadm_id = c.hadm_id
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;