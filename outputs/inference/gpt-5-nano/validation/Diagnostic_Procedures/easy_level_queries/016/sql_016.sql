WITH eligible_hadm AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
  GROUP BY a.hadm_id
),
ecg_counts AS (
  SELECT eh.hadm_id,
         COUNT(DISTINCT CASE
           WHEN ce.itemid IS NOT NULL
                AND (LOWER(di.label) LIKE '%ecg%' OR
                     LOWER(di.label) LIKE '%ekg%' OR
                     LOWER(di.label) LIKE '%telemetry%')
           THEN ce.itemid
         END) AS distinct_proc_count
  FROM eligible_hadm eh
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.hadm_id = eh.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` ce
    ON ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  GROUP BY eh.hadm_id
)
SELECT PERCENTILE_CONT(distinct_proc_count, 0.75) OVER () AS percentile_75
FROM ecg_counts
LIMIT 1;