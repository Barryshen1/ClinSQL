WITH pe_cohort AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = d.subject_id
  WHERE (
          d.icd_code LIKE 'I26%'      -- ICD-10: Pulmonary embolism
          OR d.icd_code LIKE '415%'     -- ICD-9: Pulmonary embolism (and related)
        )
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),

first_icu AS (
  SELECT t.subject_id, t.hadm_id, t.stay_id, t.intime
  FROM (
    SELECT ic.subject_id,
           ic.hadm_id,
           ic.stay_id,
           ic.intime,
           ROW_NUMBER() OVER (PARTITION BY ic.subject_id ORDER BY ic.intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    WHERE ic.subject_id IN (SELECT subject_id FROM pe_cohort)
  ) AS t
  WHERE t.rn = 1
),

intensity AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime,
         COUNT(DISTINCT pe.itemid) AS intensity_count
  FROM first_icu AS f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.stay_id = f.stay_id
   AND pe.starttime >= f.intime
   AND pe.starttime < TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id, f.hadm_id, f.stay_id, f.intime
),

cohort_metrics AS (
  SELECT i.subject_id,
         i.intensity_count,
         a.hadm_id,
         (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS hosp_los_days,
         a.hospital_expire_flag AS mortality
  FROM intensity AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = i.hadm_id
)

SELECT
  quintile,
  AVG(intensity_count) AS avg_proc_count,
  AVG(hosp_los_days) AS avg_hosp_los_days,
  100.0 * AVG(mortality) AS mortality_percent
FROM (
  SELECT intensity_count,
         hosp_los_days,
         mortality,
         NTILE(5) OVER (ORDER BY intensity_count) AS quintile
  FROM cohort_metrics
) AS t
GROUP BY quintile
ORDER BY quintile;