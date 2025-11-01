WITH cohort AS (
  SELECT 
    a.hadm_id,
    CASE WHEN los <= 4 THEN '1-4' ELSE '5-8' END AS los_grp,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  CROSS JOIN UNNEST([DATE_DIFF(a.dischtime, a.admittime, DAY)]) AS los
  CROSS JOIN UNNEST([p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year]) AS age
  WHERE p.gender = 'M'
    AND age BETWEEN 77 AND 87
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%asthma%'
    AND (LOWER(dd.long_title) LIKE '%exacerbation%' 
         OR LOWER(dd.long_title) LIKE '%acute asthma%' 
         OR LOWER(dd.long_title) LIKE '%status asthmaticus%')
    AND los BETWEEN 1 AND 8
  GROUP BY a.hadm_id, los
),
imaging AS (
  SELECT 
    proc.hadm_id,
    COUNT(*) AS num_ctmri
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ct%' 
     OR LOWER(dp.long_title) LIKE '%mri%' 
     OR LOWER(dp.long_title) LIKE '%computed tomography%' 
     OR LOWER(dp.long_title) LIKE '%magnetic resonance%'
  GROUP BY proc.hadm_id
)
SELECT 
  c.los_grp,
  c.icu_flag,
  AVG(COALESCE(im.num_ctmri, 0)) AS mean_ctmri,
  MIN(COALESCE(im.num_ctmri, 0)) AS min_ctmri,
  MAX(COALESCE(im.num_ctmri, 0)) AS max_ctmri
FROM cohort c
LEFT JOIN imaging im 
  ON c.hadm_id = im.hadm_id
GROUP BY c.los_grp, c.icu_flag
ORDER BY c.los_grp, c.icu_flag;