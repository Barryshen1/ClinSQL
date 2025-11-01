WITH patients_ich AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('431', '430', '432', '4320', '4321', '4329'))
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
    )
),

med_complexity AS (
  SELECT 
    pi.hadm_id,
    COUNT(DISTINCT CONCAT(pr.drug, '|', pr.route)) AS med_complexity_score
  FROM patients_ich pi
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pi.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= pi.admittime
    AND pr.starttime <= pi.admittime + INTERVAL '48' HOUR
  GROUP BY pi.hadm_id
),

quartiles AS (
  SELECT 
    hadm_id,
    med_complexity_score,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS quartile
  FROM med_complexity
),

readmissions AS (
  SELECT 
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit30
  FROM patients_ich a1
  LEFT JOIN patients_ich a2 
    ON a1.subject_id = a2.subject_id 
    AND a2.admittime > a1.dischtime 
    AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
)

SELECT
  q.quartile,
  COUNT(*) AS admissions,
  MIN(q.med_complexity_score) AS min_score,
  MAX(q.med_complexity_score) AS max_score,
  ROUND(AVG(DATETIME_DIFF(pi.dischtime, pi.admittime, SECOND) / 86400.0), 2) AS avg_los_days,
  ROUND(AVG(pi.hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(r.readmit30) * 100, 2) AS readmission_30day_pct
FROM quartiles q
JOIN patients_ich pi ON q.hadm_id = pi.hadm_id
JOIN readmissions r ON q.hadm_id = r.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;