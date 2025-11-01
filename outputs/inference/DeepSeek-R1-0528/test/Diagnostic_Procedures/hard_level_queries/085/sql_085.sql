WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code IN ('5781', '5789', '5693'))
      OR (icd_version = 10 AND icd_code IN ('K625', 'K922'))
  ) diag
    ON i.hadm_id = diag.hadm_id AND i.subject_id = diag.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
first_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM cohort
  WHERE stay_rank = 1
),
procedure_counts AS (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.los,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM first_stay fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fs.stay_id = pe.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime < DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
  GROUP BY fs.subject_id, fs.hadm_id, fs.stay_id, fs.los
),
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedure_counts
),
with_mortality AS (
  SELECT
    wq.*,
    adm.hospital_expire_flag
  FROM with_quintile wq
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON wq.hadm_id = adm.hadm_id
)
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_percent
FROM with_mortality
GROUP BY quintile
ORDER BY quintile;