WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.subject_id = diag.subject_id
        AND adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code = 'J441')
          OR (diag.icd_version = 9 AND diag.icd_code = '49121')
        )
    )
),

meds_complexity AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

with_tertile AS (
  SELECT 
    c.*,
    COALESCE(mc.complexity_score, 0) AS complexity_score,
    NTILE(3) OVER (ORDER BY COALESCE(mc.complexity_score, 0)) AS tertile
  FROM cohort c
  LEFT JOIN meds_complexity mc
    ON c.hadm_id = mc.hadm_id AND c.subject_id = mc.subject_id
),

readmission_flag AS (
  SELECT 
    wt.*,
    CASE 
      WHEN wt.hospital_expire_flag = 1 THEN 0  -- died in hospital, cannot be readmitted
      ELSE 
        CASE WHEN EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
          WHERE readm.subject_id = wt.subject_id
            AND readm.admittime > wt.dischtime
            AND readm.admittime <= DATETIME_ADD(wt.dischtime, INTERVAL 30 DAY)
        ) THEN 1 ELSE 0 END
    END AS readmitted_30d
  FROM with_tertile wt
)

SELECT 
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  AVG(complexity_score) AS mean_complexity,
  AVG(los_days) AS mean_los,
  100 * AVG(hospital_expire_flag) AS mortality_pct,
  100 * AVG(readmitted_30d) AS readmission_30d_pct
FROM readmission_flag
GROUP BY tertile
ORDER BY tertile;