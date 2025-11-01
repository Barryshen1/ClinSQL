WITH cardiac_arrest AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age,
         adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '4275')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I46%')
    )
),
meds_7day AS (
  SELECT ca.hadm_id,
         COUNT(DISTINCT LOWER(pres.drug)) AS unique_drugs,
         COUNT(DISTINCT CASE 
                          WHEN LOWER(pres.drug) IN (
                            'epinephrine','norepinephrine','dopamine','dobutamine',
                            'amiodarone','lidocaine','vasopressin'
                          ) THEN LOWER(pres.drug)
                        END) AS high_risk_drugs,
         COUNT(DISTINCT LOWER(pres.route)) AS unique_routes
  FROM cardiac_arrest ca
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON ca.hadm_id = pres.hadm_id
  WHERE pres.starttime >= ca.admittime
    AND pres.starttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 7 DAY)
  GROUP BY ca.hadm_id
),
score_calc AS (
  SELECT ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime,
         ca.hospital_expire_flag,
         meds.unique_drugs,
         meds.high_risk_drugs,
         meds.unique_routes,
         (meds.unique_drugs + 2 * meds.high_risk_drugs + meds.unique_routes) AS complexity_score
  FROM cardiac_arrest ca
  LEFT JOIN meds_7day meds
    ON ca.hadm_id = meds.hadm_id
),
with_tertile AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM score_calc
),
readmission_flag AS (
  SELECT a.subject_id, a.hadm_id,
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` nextadm
           WHERE nextadm.subject_id = a.subject_id
             AND nextadm.admittime > a.dischtime
             AND nextadm.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
         ) THEN 1 ELSE 0 END AS readmit_30d
  FROM with_tertile a
)
SELECT t.tertile,
       COUNT(*) AS n_admissions,
       MIN(t.complexity_score) AS min_score,
       MAX(t.complexity_score) AS max_score,
       ROUND(AVG(TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY)),2) AS mean_los_days,
       ROUND(100.0 * SUM(CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*),2) AS in_hosp_mortality_pct,
       ROUND(100.0 * SUM(r.readmit_30d)/COUNT(*),2) AS readmit_30day_pct
FROM with_tertile t
JOIN readmission_flag r
  ON t.hadm_id = r.hadm_id
GROUP BY tertile
ORDER BY tertile;