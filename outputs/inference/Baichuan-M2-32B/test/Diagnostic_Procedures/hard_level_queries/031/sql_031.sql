WITH eligible_icu AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = i.subject_id
        AND d.hadm_id = i.hadm_id
        AND d.icd_code = 'E11.21'
        AND d.icd_version = 10
    )
),
procedures_48h AS (
  SELECT 
    e.stay_id,
    e.hadm_id,
    COUNT(p.*) AS procedure_count
  FROM eligible_icu e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON e.subject_id = p.subject_id
    AND e.hadm_id = p.hadm_id
    AND p.chartdate BETWEEN DATE(e.intime) AND DATE(DATE_ADD(e.intime, INTERVAL 48 HOUR))
  GROUP BY e.stay_id, e.hadm_id
),
with_quintile AS (
  SELECT 
    p.*,
    NTILE(5) OVER (ORDER BY p.procedure_count) AS quintile
  FROM procedures_48h p
),
next_adm AS (
  SELECT 
    subject_id,
    hadm_id,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmission_flags AS (
  SELECT 
    n.subject_id,
    n.hadm_id,
    CASE 
      WHEN n.next_admittime BETWEEN n.dischtime AND DATE_ADD(n.dischtime, INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS readmitted
  FROM next_adm n
)
SELECT 
  w.quintile,
  COUNT(DISTINCT w.stay_id) AS num_icu_stays,
  AVG(w.procedure_count) AS mean_procedures,
  MIN(w.procedure_count) AS min_procedures,
  MAX(w.procedure_count) AS max_procedures,
  AVG(CASE WHEN e.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS mortality_percent,
  AVG(TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY)) AS mean_los_days,
  AVG(CASE WHEN r.readmitted = 1 THEN 1.0 ELSE 0 END) * 100 AS readmission_percent
FROM with_quintile w
INNER JOIN eligible_icu e 
  ON w.stay_id = e.stay_id AND w.hadm_id = e.hadm_id
INNER JOIN readmission_flags r 
  ON e.hadm_id = r.hadm_id AND e.subject_id = r.subject_id
GROUP BY w.quintile
ORDER BY w.quintile;