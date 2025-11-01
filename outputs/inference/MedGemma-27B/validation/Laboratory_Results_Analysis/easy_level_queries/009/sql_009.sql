WITH ACS_Patients AS (
  -- Identify patients admitted with Acute Coronary Syndrome (ACS)
  SELECT DISTINCT
    p.subject_id,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND d.icd_code IN ('410', '411', '413', '414', '420', '421', '422', '427', '428', '429', '440', '441', '442', '443', '446', '447', '448', '449', '460', '461', '462', '463', '464', '465', '466', '467', '468', '469', '480', '481', '482', '483', '484', '485', '486', '487', '488', '489', '490', '491', '492', '493', '494', '495', '496', '497', '498', '499', '520', '521', '522', '523', '524', '525', '526', '527', '528', '529', '580', '581', '582', '583', '584', '585', '586', '587', '588', '589', '590', '591', '592', '593', '594', '595', '596', '597', '598', '599', '620', '621', '622', '623', '624', '625', '626', '627', '628', '629', '630', '631', '632', '633', '634', '635', '636', '637', '638', '639', '640', '641', '642', '643', '644', '645', '646', '647', '648', '649', '650', '651', '652', '653', '654', '655', '656', '657', '658', '659', '660', '661', '662', '663', '664', '665', '666', '667', '668', '669', '670', '671', '672', '673', '674', '675', '676', '677', '678', '679') -- Fixed the unclosed string literal
),
  TroponinMeasurements AS (
    -- Select troponin measurements for ACS patients
    SELECT
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.valuenum AS troponin_value
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE
      le.subject_id IN (SELECT subject_id FROM ACS_Patients)
      AND dli.label LIKE 'Troponin%'
  ),
  NadirTroponin AS (
    -- Calculate the nadir troponin for each patient
    SELECT
      subject_id,
      hadm_;