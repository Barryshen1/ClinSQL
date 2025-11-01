WITH pe_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON d.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE d.icd_code LIKE 'I26%'
    AND d.icd_version = 10
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),
cancer AS (
  SELECT subject_id, 1 AS has_cancer
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'C%'
    AND icd_version = 10
  GROUP BY subject_id
),
chronic_heart AS (
  SELECT subject_id, 1 AS has_chronic_heart
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_code LIKE 'I25%' OR icd_code LIKE 'I50%')
    AND icd_version = 10
  GROUP BY subject_id
),
chronic_lung AS (
  SELECT subject_id, 1 AS has_chronic_lung
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_code LIKE 'J44%' OR icd_code LIKE 'J43%')
    AND icd_version = 10
  GROUP BY subject_id
),
pulse_gt110 AS (
  SELECT 
    c.subject_id,
    1 AS pulse_gt110
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN pe_patients p ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE c.itemid = 220045
    AND c.valuenum > 110
  GROUP BY c.subject_id
),
systolic_lt100 AS (
  SELECT 
    c.subject_id,
    1 AS systolic_lt100
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN pe_patients p ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE c.itemid = 220050
    AND c.valuenum < 100
  GROUP BY c.subject_id
),
age_gt80 AS (
  SELECT 
    subject_id,
    CASE WHEN anchor_age > 80 THEN 1 ELSE 0 END AS age_gt80
  FROM pe_patients
),
pesi_vars AS (
  SELECT 
    p.subject_id,
    COALESCE(c.has_cancer, 0) AS has_cancer,
    COALESCE(ch.has_chronic_heart, 0) AS has_chronic_heart,
    COALESCE(cl.has_chronic_lung, 0) AS has_chronic_lung,
    COALESCE(pg.pulse_gt110, 0) AS pulse_gt110,
    COALESCE(sl.systolic_lt100, 0) AS systolic_lt100,
    a.age_gt80
  FROM pe_patients p
  LEFT JOIN cancer c ON p.subject_id = c.subject_id
  LEFT JOIN chronic_heart ch ON p.subject_id = ch.subject_id
  LEFT JOIN chronic_lung cl ON p.subject_id = cl.subject_id
  LEFT JOIN pulse_gt110 pg ON p.subject_id = pg.subject_id
  LEFT JOIN systolic_lt100 sl ON p.subject_id = sl.subject_id
  LEFT JOIN age_gt80 a ON p.subject_id = a.subject_id
),
pesi_scores AS (
  SELECT 
    subject_id,
    (age_gt80 + has_cancer + has_chronic_heart + has_chronic_lung + pulse_gt110 + systolic_lt100) AS pesi_score
  FROM pesi_vars
),
quintiles AS (
  SELECT 
    p.*,
    ps.pesi_score,
    NTILE(5) OVER (ORDER BY ps.pesi_score) AS quintile
  FROM pe_patients p
  JOIN pesi_scores ps ON p.subject_id = ps.subject_id
),
aki AS (
  SELECT subject_id, 1 AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'N17%'
    AND icd_version = 10
  GROUP BY subject_id
),
ards AS (
  SELECT subject_id, 1 AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code = 'J80'
    AND icd_version = 10
  GROUP BY subject_id
),
overall_mortality AS (
  SELECT 
    AVG(CASE WHEN dod IS NOT NULL AND dod <= admittime + INTERVAL 90 DAY THEN 1 ELSE 0 END) AS overall_mortality
  FROM quintiles
)
SELECT 
  q.quintile,
  AVG(CASE WHEN q.dod IS NOT NULL AND q.dod <= q.admittime + INTERVAL 90 DAY THEN 1 ELSE 0 END) AS mortality_rate,
  om.overall_mortality AS comparison_mortality,
  AVG(COALESCE(a.has_aki, 0)) AS aki_rate,
  AVG(COALESCE(ar.has_ards, 0)) AS ards_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY 
    CASE 
      WHEN q.dod IS NULL OR q.dod > q.admittime + INTERVAL 90 DAY 
      THEN EXTRACT(DAY FROM (q.dischtime - q.admittime)) 
    END
  ) AS median_survivor_los
FROM quintiles q
LEFT JOIN aki a ON q.subject_id = a.subject_id
LEFT JOIN ards ar ON q.subject_id = ar.subject_id
CROSS JOIN overall_mortality om
GROUP BY q.quintile, om.overall_mortality
ORDER BY q.quintile;