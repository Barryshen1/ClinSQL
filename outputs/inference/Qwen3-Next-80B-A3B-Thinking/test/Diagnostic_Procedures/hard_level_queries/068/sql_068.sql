WITH admissions_criteria AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND di.seq_num = 1
    AND (d.long_title LIKE '%asthma%' AND (d.long_title LIKE '%exacerbation%' OR d.long_title LIKE '%acute%'))
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),
icu_stays AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.hospital_expire_flag,
    a.los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN admissions_criteria a
    ON i.hadm_id = a.hadm_id
),
proc_count AS (
  SELECT
    i.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL 72 HOUR
  GROUP BY i.stay_id
),
quartiles AS (
  SELECT
    pc.procedure_count,
    i.los_days,
    i.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.procedure_count) AS quartile
  FROM proc_count pc
  JOIN icu_stays i
    ON pc.stay_id = i.stay_id
)
SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM quartiles
GROUP BY quartile
ORDER BY quartile;