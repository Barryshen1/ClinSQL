WITH cardiac_arrest_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%cardiac arrest%'
),

cohort AS (
  SELECT a.hadm_id,
         a.admittime,
         a.dischtime,
         a.deathtime,
         p.subject_id,
         p.gender,
         p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cardiac_arrest_hadm ca ON a.hadm_id = ca.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE (LOWER(p.gender) = 'f' OR p.gender = 'Female')
    AND p.anchor_age BETWEEN 78 AND 88
),

high_risk_drugs AS (
  SELECT 'insulin' AS drug
  UNION ALL SELECT 'dopamine'
  UNION ALL SELECT 'norepinephrine'
  UNION ALL SELECT 'epinephrine'
  UNION ALL SELECT 'vasopressin'
  UNION ALL SELECT 'heparin'
  UNION ALL SELECT 'warfarin'
  UNION ALL SELECT 'potassium chloride'
  UNION ALL SELECT 'potassium'
  UNION ALL SELECT 'magnesium sulfate'
  UNION ALL SELECT 'digoxin'
),

meds AS (
  SELECT c.hadm_id,
         COUNT(DISTINCT LOWER(p.drug)) AS unique_drugs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
   AND p.starttime >= c.admittime
   AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),

high_risk AS (
  SELECT c.hadm_id,
         COUNT(DISTINCT LOWER(p.drug)) AS high_risk_drugs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
   AND p.starttime >= c.admittime
   AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  JOIN high_risk_drugs hrd
    ON LOWER(p.drug) = LOWER(hrd.drug)
  GROUP BY c.hadm_id
),

routes AS (
  SELECT c.hadm_id,
         COUNT(DISTINCT p.route) AS routes
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
   AND p.starttime >= c.admittime
   AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  WHERE p.route IS NOT NULL
  GROUP BY c.hadm_id
),

score AS (
  SELECT c.hadm_id,
         COALESCE(m.unique_drugs, 0) AS unique_drugs,
         COALESCE(hr.high_risk_drugs, 0) AS high_risk_drugs,
         COALESCE(r.routes, 0) AS routes,
         (COALESCE(m.unique_drugs, 0) + 2 * COALESCE(hr.high_risk_drugs, 0) + COALESCE(r.routes, 0)) AS score,
         c.subject_id,
         c.admittime,
         c.dischtime,
         c.deathtime
  FROM cohort c
  LEFT JOIN meds m ON c.hadm_id = m.hadm_id
  LEFT JOIN high_risk hr ON c.hadm_id = hr.hadm_id
  LEFT JOIN routes r ON c.hadm_id = r.hadm_id
),

tert AS (
  SELECT s.hadm_id,
         s.subject_id,
         s.admittime,
         s.dischtime,
         s.deathtime,
         s.score,
         NTILE(3) OVER (ORDER BY s.score) AS tertile
  FROM score s
),

los AS (
  SELECT t.hadm_id,
         t.subject_id,
         t.admittime,
         t.dischtime,
         t.deathtime,
         t.score,
         t.tertile,
         TIMESTAMP_DIFF(t.dischtime, t.admittime, SECOND) / 86400.0 AS los_days
  FROM tert t
),

readmit AS (
  SELECT l.*,
         LEAD(l.admittime) OVER (PARTITION BY l.subject_id ORDER BY l.admittime) AS next_admittime
  FROM los l
),

readmit_flag AS (
  SELECT r.*,
         CASE
           WHEN r.next_admittime IS NOT NULL
                AND r.next_admittime <= TIMESTAMP_ADD(r.dischtime, INTERVAL 30 DAY)
           THEN 1 ELSE 0 END AS readmit_30d
  FROM readmit r
)

SELECT
  tertile,
  COUNT(*) AS admissions,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  AVG(los_days) AS mean_los_days,
  100 * SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_percent,
  100 * AVG(readmit_30d) AS readmission_30day_percent
FROM readmit_flag
GROUP BY tertile
ORDER BY tertile;