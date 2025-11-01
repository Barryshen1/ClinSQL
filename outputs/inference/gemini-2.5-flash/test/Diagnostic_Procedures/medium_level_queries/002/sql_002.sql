WITH
  AdmissionCohort AS ( -- Renamed and fixed AS keyword for the first CTE
    SELECT
      a.subject_id,
      a.hadm_id,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
      CASE
        WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE NULL -- This case should not be reached due to the outer LOS filter
      END AS los_group
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      -- Calculate age at admission
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
      AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
      AND EXISTS ( -- Ensure the admission has a TIA diagnosis
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE
          di.subject_id = a.subject_id
          AND di.hadm_id = a.hadm_id
          AND (
            -- ICD-10 codes for Transient Ischemic Attack (TIA)
            (di.icd_code LIKE 'G45%' AND di.icd_version = 10)
            -- ICD-9 codes for Transient Ischemic Attack (TIA)
            OR (di.icd_code LIKE '435%' AND di.icd_version = 9)
          )
      )
  ),
  ICUAdmissions AS ( -- Renamed for clarity
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  ProcedureCounts AS ( -- Renamed for clarity
    SELECT
      pi.hadm_id,
      COUNT(pi.icd_code) AS num_procedures -- Count each relevant procedure record
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON pi.icd_code = dp.icd_code
      AND pi.icd_version = dp.icd_version
    WHERE
      -- Filter for relevant ultrasound/echocardiogram procedures by long_title
      -- Using LOWER() for case-insensitive matching in BigQuery, as ILIKE is not supported.
      (
        LOWER(dp.long_title) LIKE '%echocardiogram%'
        OR LOWER(dp.long_title) LIKE '%ultrasound%heart%'
        OR LOWER(dp.long_title) LIKE '%ultrasound%cardiac%'
        OR LOWER(dp.long_title) LIKE '%ultrasound%cerebral%'
        OR LOWER(dp.long_title) LIKE '%ultrasound%carotid%'
      )
    GROUP BY
      pi.hadm_id
  )
SELECT
  ac.los_group,
  -- Explicitly define has_icu_stay for the SELECT and GROUP BY clause
  CASE
    WHEN ia.hadm_id IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS has_icu_stay,
  -- Calculate the mean number of procedures, handling cases where no procedures are found (COALESCE to 0).
  AVG(COALESCE(pc.num_procedures, 0)) AS mean_ultrasounds_echos_per_admission
FROM
  AdmissionCohort AS ac
LEFT JOIN
  ICUAdmissions AS ia
  ON ac.hadm_id = ia.hadm_id
LEFT JOIN
  ProcedureCounts AS pc
  ON ac.hadm_id = pc.hadm_id
GROUP BY
  ac.los_group,
  has_icu_stay -- This column must be in the GROUP BY clause if it's in SELECT and not aggregated
ORDER BY
  ac.los_group,
  has_icu_stay;