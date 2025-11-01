WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    a.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
        )
    ) THEN 1 ELSE 0 END AS has_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),
procedure_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(CASE WHEN di.label LIKE '%CT%' OR di.label LIKE '%MRI%' OR di.label LIKE '%Lumbar%' THEN pe.itemid END) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  GROUP BY c.subject_id, c.hadm_id
)
SELECT
  c.has_hemorrhagic_stroke,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY pc.num_procedures) AS percentile_90_procedures,
  AVG(c.los) AS avg_los,
  AVG(c.hospital_expire_flag) AS mortality_rate
FROM cohort c
JOIN procedure_counts pc ON c.subject_id = pc.subject_id AND c.hadm_id = pc.hadm_id
GROUP BY c.has_hemorrhagic_stroke;