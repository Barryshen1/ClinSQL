WITH admissions_filtered AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND SUBSTR(d.icd_code, 1, 3) IN ('T00','T01','T02','T03','T04','T05','T06','T07')
    )
),
complexity_scores AS (
  SELECT 
    af.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM admissions_filtered af
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON af.hadm_id = pr.hadm_id
    AND pr.starttime < DATETIME_ADD(af.admittime, INTERVAL 7 DAY)
    AND (pr.stoptime IS NULL OR pr.stoptime > af.admittime)
  GROUP BY af.hadm_id
),
with_readmission AS (
  SELECT 
    af.hadm_id,
    af.hospital_expire_flag,
    DATETIME_DIFF(af.dischtime, af.admittime, SECOND) / (24 * 60 * 60) AS los_hospital,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = af.subject_id
          AND a2.hadm_id != af.hadm_id
          AND a2.admittime > af.dischtime
          AND a2.admittime <= DATETIME_ADD(af.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmission_30d
  FROM admissions_filtered af
),
combined AS (
  SELECT 
    cs.hadm_id,
    cs.complexity_score,
    wr.hospital_expire_flag,
    wr.los_hospital,
    wr.readmission_30d
  FROM complexity_scores cs
  INNER JOIN with_readmission wr
    ON cs.hadm_id = wr.hadm_id
),
tertiles AS (
  SELECT 
    hadm_id,
    complexity_score,
    hospital_expire_flag,
    los_hospital,
    readmission_30d,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM combined
)
SELECT 
  tertile,
  COUNT(*) AS admissions,
  AVG(complexity_score) AS mean_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los_hospital) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmission_30d) * 100 AS readmission_30d_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;