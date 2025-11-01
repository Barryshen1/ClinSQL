WITH hhs_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,  -- Compute hospital LOS
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND (
      LOWER(d_icd.long_title) LIKE '%hyperosmolar%'
      OR LOWER(d_icd.long_title) LIKE '%hyperglycemic%'
      OR d.icd_code IN ('E11.01', 'E10.01')
    )
),

procedure_count_48h AS (
  SELECT
    i.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
  WHERE pe.starttime >= i.intime
    AND pe.starttime <= TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY i.stay_id
),

readmission_30d AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_30d_flag
  FROM hhs_patients a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
),

icu_with_procedures AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    pc.procedure_count,
    hp.hospital_expire_flag,
    hp.los,
    hp.anchor_age,
    hp.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN hhs_patients hp ON i.hadm_id = hp.hadm_id
  LEFT JOIN procedure_count_48h pc ON i.stay_id = pc.stay_id
),

final_with_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY COALESCE(procedure_count, 0)) AS quintile
  FROM icu_with_procedures
)

SELECT
  quintile,
  COUNT(*) AS num_icu_stays,
  AVG(COALESCE(procedure_count, 0)) AS mean_procedures,
  MIN(COALESCE(procedure_count, 0)) AS min_procedures,
  MAX(COALESCE(procedure_count, 0)) AS max_procedures,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct,
  AVG(los) AS mean_hospital_los,
  AVG(COALESCE(r.readmission_30d_flag, 0)) * 100 AS readmission_30d_pct
FROM final_with_quintiles f
LEFT JOIN readmission_30d r ON f.hadm_id = r.hadm_id
GROUP BY quintile
ORDER BY quintile;