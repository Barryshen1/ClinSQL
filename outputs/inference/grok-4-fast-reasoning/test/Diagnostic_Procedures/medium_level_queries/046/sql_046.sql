WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND (d.icd_code = '435.9' OR d.icd_code = 'G45.9')
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
procedures AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_ctmri
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE (LOWER(h.short_description) LIKE '%ct%' AND (LOWER(h.short_description) LIKE '%head%' OR LOWER(h.short_description) LIKE '%brain%'))
     OR (LOWER(h.short_description) LIKE '%mri%' AND (LOWER(h.short_description) LIKE '%head%' OR LOWER(h.short_description) LIKE '%brain%'))
  GROUP BY hadm_id
)
SELECT 
  c.los_group,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  AVG(COALESCE(proc.num_ctmri, 0)) AS mean_ctmri_per_admission
FROM cohort c
LEFT JOIN procedures proc
  ON c.hadm_id = proc.hadm_id
GROUP BY c.los_group
ORDER BY c.los_group;