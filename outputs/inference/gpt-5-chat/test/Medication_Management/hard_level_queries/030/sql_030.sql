WITH pancreatitis_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 71 AND 81
    -- Acute pancreatitis ICD-9 and ICD-10:
    AND (
         (dx.icd_version = 9 AND dx.icd_code LIKE '5770%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'K85%')
    )
),
medications_72h AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity
  FROM pancreatitis_cohort p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime <= DATETIME_ADD(p.admittime, INTERVAL 72 HOUR)
    AND pr.starttime >= p.admittime
  GROUP BY p.subject_id, p.hadm_id
),
cohort_with_score AS (
  SELECT
    p.*,
    COALESCE(m.med_complexity, 0) AS med_complexity
  FROM pancreatitis_cohort p
  LEFT JOIN medications_72h m
    ON p.subject_id = m.subject_id
    AND p.hadm_id = m.hadm_id
),
with_tertile AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_complexity) AS tertile
  FROM cohort_with_score
),
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    CASE 
      WHEN MIN(a2.admittime) IS NOT NULL THEN 1 ELSE 0
    END AS readmit_30d
  FROM cohort_with_score a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY a1.subject_id, a1.hadm_id
)
SELECT
  w.tertile,
  COUNT(*) AS n_admissions,
  AVG(TIMESTAMP_DIFF(w.dischtime, w.admittime, HOUR)/24.0) AS mean_los_days,
  AVG(w.hospital_expire_flag) AS in_hosp_mortality_rate,
  AVG(r.readmit_30d) AS readmit_30d_rate
FROM with_tertile w
JOIN readmissions r
  ON w.subject_id = r.subject_id
  AND w.hadm_id = r.hadm_id
GROUP BY w.tertile
ORDER BY w.tertile;