WITH lgib_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(dd.long_title) LIKE '%lower gastrointestinal%'
),
first_icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.los,
         ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
proc_counts AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime, f.los,
         COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_icu_stays f
  JOIN lgib_patients lp
    ON f.subject_id = lp.subject_id AND f.hadm_id = lp.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id AND f.hadm_id = pe.hadm_id AND f.stay_id = pe.stay_id
    AND pe.starttime >= f.intime
    AND pe.starttime < DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  WHERE f.rn = 1
  GROUP BY f.subject_id, f.hadm_id, f.stay_id, f.intime, f.los
),
mortality AS (
  SELECT hadm_id, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT quintile,
       AVG(proc_count) AS mean_proc_count,
       AVG(los) AS mean_icu_los_days,
       100 * SUM(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_percent
FROM (
  SELECT pc.*, m.hospital_expire_flag,
         NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts pc
  JOIN mortality m
    ON pc.hadm_id = m.hadm_id
) q
GROUP BY quintile
ORDER BY quintile;