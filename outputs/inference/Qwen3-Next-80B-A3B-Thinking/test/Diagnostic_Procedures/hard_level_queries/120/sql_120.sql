WITH admissions_criteria AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
    AND d.icd_code IN ('K25.0', 'K26.0', 'K27.0', 'K28.0', 'K22.11', 'K92.2')
),

first_icu AS (
  SELECT
    hadm_id,
    stay_id,
    intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) = 1
),

procedures_count AS (
  SELECT
    f.hadm_id,
    COUNT(pe.itemid) AS procedure_count
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
    AND pe.starttime BETWEEN f.intime AND f.intime + INTERVAL '72' HOUR
  GROUP BY f.hadm_id
),

los_mortality AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
    hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM (
  SELECT
    pc.procedure_count,
    lm.los_days,
    lm.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.procedure_count) AS quartile
  FROM procedures_count pc
  JOIN los_mortality lm ON pc.hadm_id = lm.hadm_id
  JOIN admissions_criteria ac ON pc.hadm_id = ac.hadm_id
) AS quartiles
GROUP BY quartile
ORDER BY quartile;