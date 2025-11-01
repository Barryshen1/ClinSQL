WITH RelevantPatients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
), PatientICUStayDetails AS (
  SELECT
    rp.subject_id,
    rp.stay_id,
    rp.intime,
    rp.outtime,
    ce.charttime,
    ce.itemid,
    ce.value,
    ce.valuenum,
    ce.valueuom
  FROM RelevantPatients AS rp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON rp.subject_id = ce.subject_id AND rp.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (
      SELECT
        itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label LIKE 'GCS Total%'
    )
), ICUStayDay AS (
  SELECT
    psd.subject_id,
    psd.stay_id,
    psd.intime,
    psd.outtime,
    psd.charttime,
    psd.valuenum,
    DATE_DIFF(psd.charttime, psd.intime, DAY) AS icu_day
  FROM PatientICUStayDetails AS psd
), HighFlowNasalCannulaPatients AS (
  SELECT
    psd.subject_id,
    psd.stay_id,
    psd.intime,
    psd.outtime,
    psd.charttime,
    psd.valuenum,
    psd.icu_day
  FROM PatientICUStayDetails AS psd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS emar
    ON psd.subject_id = emar.subject_id AND psd.hadm_id = emar.hadm_id -- Changed stay_id to hadm_id
  WHERE
    emar.medication LIKE '%high flow nasal cannula%'
), FinalGCS AS (
  SELECT
    hfncp.subject_id,
    hfncp.stay_id,
    hfncp.intime,
    hfncp.outtime,
    hfncp.charttime,
    hfncp.valuenum,
    hfncp.icu_day
  FROM HighFlowNasalCannulaPatients AS hfncp
  WHERE
    hfncp.icu_day >= 2
)
SELECT
  MEDIAN(valuenum) AS median_gcs_total
FROM FinalGCS;