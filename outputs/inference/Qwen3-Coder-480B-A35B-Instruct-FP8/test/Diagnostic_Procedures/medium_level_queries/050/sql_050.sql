WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
stay_groups AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS stay_group
  FROM
    admissions_filtered
  WHERE
    los_days BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT
    s.stay_group,
    s.hadm_id,
    COUNT(*) AS proc_count
  FROM
    stay_groups s
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
  ON
    s.hadm_id = proc.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dproc
  ON
    proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%imaging%' OR LOWER(dproc.long_title) LIKE '%radiology%'
  GROUP BY
    s.stay_group, s.hadm_id
)
SELECT
  stay_group,
  AVG(proc_count) AS mean_procedures,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures
FROM
  procedure_counts
GROUP BY
  stay_group
ORDER BY
  stay_group;