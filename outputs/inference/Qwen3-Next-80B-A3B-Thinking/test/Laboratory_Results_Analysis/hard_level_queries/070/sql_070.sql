WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    )
),

lab_score_cohort AS (
  SELECT 
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN cohort c ON l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL 72 HOUR
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY l.hadm_id
),

lab_score_general AS (
  SELECT 
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 72 HOUR
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY l.hadm_id
),

quartiles AS (
  SELECT 
    NTILE(4) OVER (ORDER BY COALESCE(l.lab_instability_score, 0)) AS quartile,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(l.lab_instability_score, 0) AS lab_instability_score
  FROM cohort c
  LEFT JOIN lab_score_cohort l ON c.hadm_id = l.hadm_id
)

SELECT 
  'Cohort Quartile ' || CAST(quartile AS STRING) AS group_name,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(lab_instability_score) AS avg_lab_score
FROM quartiles
GROUP BY quartile

UNION ALL

SELECT 
  'General Population' AS group_name,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los,
  AVG(a.hospital_expire_flag) AS mortality_rate,
  AVG(COALESCE(lg.lab_instability_score, 0)) AS avg_lab_score
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
LEFT JOIN lab_score_general lg ON a.hadm_id = lg.hadm_id;