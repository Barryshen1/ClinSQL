WITH patient_filter AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 78 AND 88
),
med_complexity AS (
  SELECT pf.hadm_id,
         COUNT(DISTINCT pr.drug) AS unique_drugs,
         COUNT(DISTINCT pr.route) AS unique_routes,
         COUNT(DISTINCT CASE WHEN LOWER(pr.drug) LIKE '%high_risk%' THEN pr.drug END) AS high_risk_drugs
  FROM patient_filter pf
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pf.hadm_id = pr.hadm_id
  WHERE pr.starttime <= DATETIME_ADD(pf.admittime, INTERVAL 7 DAY)
  GROUP BY pf.hadm_id
),
mcs_score AS (
  SELECT hadm_id,
         (unique_drugs + 2*high_risk_drugs + unique_routes) AS mcs
  FROM med_complexity
),
tertiles AS (
  SELECT hadm_id, mcs,
         NTILE(3) OVER (ORDER BY mcs) AS tertile
  FROM mcs_score
),
outcomes AS (
  SELECT t.tertile,
         COUNT(a.hadm_id) AS count_admissions,
         MIN(mcs) AS min_mcs,
         MAX(mcs) AS max_mcs,
         AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR)) AS mean_los_hours,
         AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_pct,
         AVG(CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
           WHERE a2.subject_id = a.subject_id AND a2.admittime > a.dischtime AND DATETIME_DIFF(a2.admittime, a.dischtime, DAY) <= 30
         ) THEN 1 ELSE 0 END) * 100 AS thirty_day_readmission_pct
  FROM tertiles t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  JOIN patient_filter pf ON a.hadm_id = pf.hadm_id
  GROUP BY t.tertile
)
SELECT * FROM outcomes
ORDER BY tertile;