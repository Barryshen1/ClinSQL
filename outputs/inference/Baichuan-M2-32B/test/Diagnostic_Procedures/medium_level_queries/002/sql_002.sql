WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission: birth_year = anchor_year - anchor_age, then age = admittime - birth_date
    DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- ICU use: if there is any icustay for this admission
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 64 AND 74
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
tia_admissions AS (
  SELECT DISTINCT e.*
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
  WHERE d.icd_code = 'G45' AND d.icd_version = 10
),
procedure_counts AS (
  SELECT 
    t.hadm_id,
    t.icu_use,
    -- Count procedures in 1-3 days
    SUM(CASE 
          WHEN DATE_DIFF(p.chartdate, t.admittime, DAY) + 1 BETWEEN 1 AND 3 THEN 1 
          ELSE 0 
        END) AS count_1_3,
    -- Count procedures in 4-7 days
    SUM(CASE 
          WHEN DATE_DIFF(p.chartdate, t.admittime, DAY) + 1 BETWEEN 4 AND 7 THEN 1 
          ELSE 0 
        END) AS count_4_7
  FROM tia_admissions t
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` p 
    ON t.subject_id = p.subject_id AND t.hadm_id = p.hadm_id
    AND p.chartdate BETWEEN DATE_ADD(t.admittime, INTERVAL 0 DAY) AND DATE_ADD(t.admittime, INTERVAL 7 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d_hcpcs 
    ON p.hcpcs_cd = d_hcpcs.code
    AND (d_hcpcs.short_description LIKE '%ultrasound%' 
         OR d_hcpcs.short_description LIKE '%echocardiogram%')
  GROUP BY t.hadm_id, t.icu_use
)
SELECT 
  icu_use,
  '1-3' AS day_group,
  AVG(count_1_3) AS mean_procedures
FROM procedure_counts
GROUP BY icu_use, day_group
UNION ALL
SELECT 
  icu_use,
  '4-7' AS day_group,
  AVG(count_4_7) AS mean_procedures
FROM procedure_counts
GROUP BY icu_use, day_group
ORDER BY icu_use, day_group;